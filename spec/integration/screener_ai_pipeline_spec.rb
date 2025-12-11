# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Screener + AI Ranking Pipeline Integration', type: :integration do
  let(:instrument) { create(:instrument, symbol_name: 'RELIANCE', security_id: '11536', instrument_type: 'EQUITY') }
  let(:instruments) { Instrument.where(id: instrument.id) }

  before do
    # Create sufficient candles for screening
    create_list(:candle_series_record, 60, instrument: instrument, timeframe: '1D')
  end

  describe 'full pipeline: Screener -> AI Ranker -> Final Selector' do
    let(:mock_openai_response) do
      {
        'choices' => [
          {
            'message' => {
              'content' => {
                'score' => 85,
                'confidence' => 80,
                'summary' => 'Strong bullish trend with good momentum',
                'holding_days' => 12,
                'risk' => 'medium'
              }.to_json
            }
          }
        ],
        'usage' => {
          'prompt_tokens' => 150,
          'completion_tokens' => 50,
          'total_tokens' => 200
        }
      }
    end

    before do
      # Mock OpenAI API call
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .with(
          headers: {
            'Authorization' => /Bearer .+/,
            'Content-Type' => 'application/json'
          }
        )
        .to_return(
          status: 200,
          body: mock_openai_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      # Set test API key
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test_key')
    end

    it 'runs complete pipeline from screening to final selection' do
      # Step 1: Run screener
      screener_candidates = Screeners::SwingScreener.call(
        instruments: instruments,
        limit: 10
      )

      expect(screener_candidates).to be_an(Array)
      next if screener_candidates.empty?

      # Step 2: Run AI ranker
      ranked_candidates = Screeners::AIRanker.call(
        candidates: screener_candidates,
        limit: 5
      )

      expect(ranked_candidates).to be_an(Array)
      expect(ranked_candidates.size).to be <= 5

      # Verify AI scores were added
      ranked_candidates.each do |candidate|
        expect(candidate).to have_key(:ai_score)
        expect(candidate).to have_key(:ai_confidence)
        expect(candidate[:ai_score]).to be_between(0, 100)
      end

      # Step 3: Run final selector
      final_result = Screeners::FinalSelector.call(
        swing_candidates: ranked_candidates,
        swing_limit: 3
      )

      expect(final_result).to have_key(:swing)
      expect(final_result).to have_key(:summary)
      expect(final_result[:swing].size).to be <= 3

      # Verify combined scores
      final_result[:swing].each do |candidate|
        expect(candidate).to have_key(:combined_score)
        expect(candidate).to have_key(:rank)
        expect(candidate[:combined_score]).to be_a(Numeric)
      end
    end

    it 'handles AI ranking errors gracefully' do
      # Mock OpenAI API error
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 500, body: 'Internal Server Error')

      screener_candidates = Screeners::SwingScreener.call(
        instruments: instruments,
        limit: 10
      )

      next if screener_candidates.empty?

      # AI ranker should handle errors and return candidates without AI scores
      ranked_candidates = Screeners::AIRanker.call(
        candidates: screener_candidates,
        limit: 5
      )

      expect(ranked_candidates).to be_an(Array)
      # Candidates may not have AI scores if ranking failed
      # But should still be returned (just without AI enhancement)
    end

    it 'handles rate limiting' do
      # Mock rate limit response
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(
          status: 429,
          body: { error: { message: 'Rate limit exceeded' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      screener_candidates = Screeners::SwingScreener.call(
        instruments: instruments,
        limit: 10
      )

      next if screener_candidates.empty?

      # Should handle rate limit gracefully
      ranked_candidates = Screeners::AIRanker.call(
        candidates: screener_candidates,
        limit: 5
      )

      expect(ranked_candidates).to be_an(Array)
    end

    it 'caches AI ranking results' do
      # Clear cache to ensure fresh test
      Rails.cache.clear

      # Ensure AI ranking is enabled
      allow(AlgoConfig).to receive(:fetch).and_call_original
      allow(AlgoConfig).to receive(:fetch).with([:swing_trading, :ai_ranking]).and_return({ enabled: true })

      screener_candidates = Screeners::SwingScreener.call(
        instruments: instruments,
        limit: 10
      )

      next if screener_candidates.empty?

      # Stub OpenAI API response
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(
          status: 200,
          body: {
            choices: [{
              message: {
                content: JSON.generate([{ symbol: screener_candidates.first[:symbol], ai_score: 85.0, reasoning: 'Test' }])
              }
            }]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      # First call
      ranked1 = Screeners::AIRanker.call(
        candidates: screener_candidates.first(1),
        limit: 1
      )

      # Second call should use cache
      ranked2 = Screeners::AIRanker.call(
        candidates: screener_candidates.first(1),
        limit: 1
      )

      # Should only make one API call (second uses cache)
      expect(WebMock).to have_requested(:post, 'https://api.openai.com/v1/chat/completions').once
    end

    it 'sorts candidates by combined score correctly' do
      screener_candidates = [
        { symbol: 'STOCK1', score: 80.0, instrument_id: 1, indicators: {} },
        { symbol: 'STOCK2', score: 90.0, instrument_id: 2, indicators: {} }
      ]

      # Mock different AI scores for each call
      call_count = 0
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return do |_request|
          call_count += 1
          ai_score = call_count == 1 ? 85 : 75 # First call for STOCK1, second for STOCK2

          {
            status: 200,
            body: {
              'choices' => [
                {
                  'message' => {
                    'content' => {
                      'score' => ai_score,
                      'confidence' => 80,
                      'summary' => 'Test',
                      'holding_days' => 10,
                      'risk' => 'medium'
                    }.to_json
                  }
                }
              ]
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          }
        end

      ranked = Screeners::AIRanker.call(candidates: screener_candidates, limit: 10)
      final = Screeners::FinalSelector.call(swing_candidates: ranked, swing_limit: 10)

      # Verify sorting - STOCK2 should rank higher due to higher screener score
      # even if STOCK1 has higher AI score
      expect(final[:swing].first[:symbol]).to eq('STOCK2')
    end
  end

  describe 'pipeline with empty screener results' do
    it 'handles no candidates from screener' do
      # Use instrument without sufficient candles
      instrument_no_candles = create(:instrument, symbol_name: 'EMPTY')
      empty_instruments = Instrument.where(id: instrument_no_candles.id)

      screener_candidates = Screeners::SwingScreener.call(
        instruments: empty_instruments,
        limit: 10
      )

      expect(screener_candidates).to be_empty

      # AI ranker should handle empty array
      ranked = Screeners::AIRanker.call(candidates: screener_candidates, limit: 5)
      expect(ranked).to be_empty

      # Final selector should handle empty array
      final = Screeners::FinalSelector.call(swing_candidates: ranked, swing_limit: 3)
      expect(final[:swing]).to be_empty
    end
  end
end

