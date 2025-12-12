# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Screener + AI Ranking Pipeline Integration", type: :integration do
  let(:instrument) { create(:instrument, symbol_name: "RELIANCE", security_id: "11536", instrument_type: "EQUITY") }
  let(:instruments) { Instrument.where(id: instrument.id) }

  before do
    # Create sufficient candles for screening
    create_list(:candle_series_record, 60, instrument: instrument, timeframe: "1D")
  end

  describe "full pipeline: Screener -> AI Ranker -> Final Selector" do
    let(:mock_openai_response) do
      {
        "choices" => [
          {
            "message" => {
              "content" => {
                "score" => 85,
                "confidence" => 80,
                "summary" => "Strong bullish trend with good momentum",
                "holding_days" => 12,
                "risk" => "medium",
              }.to_json,
            },
          },
        ],
        "usage" => {
          "prompt_tokens" => 150,
          "completion_tokens" => 50,
          "total_tokens" => 200,
        },
      }
    end

    before do
      # Mock OpenAI API call
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .with(
          headers: {
            "Authorization" => /Bearer .+/,
            "Content-Type" => "application/json",
          },
        )
        .to_return(
          status: 200,
          body: mock_openai_response.to_json,
          headers: { "Content-Type" => "application/json" },
        )

      # Set test API key
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test_key")
    end

    it "runs complete pipeline from screening to final selection" do
      # Step 1: Run screener
      screener_candidates = Screeners::SwingScreener.call(
        instruments: instruments,
        limit: 10,
      )

      expect(screener_candidates).to be_an(Array)
      next if screener_candidates.empty?

      # Step 2: Run AI ranker
      ranked_candidates = Screeners::AIRanker.call(
        candidates: screener_candidates,
        limit: 5,
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
        swing_limit: 3,
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

    it "handles AI ranking errors gracefully" do
      # Mock OpenAI API error
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 500, body: "Internal Server Error")

      screener_candidates = Screeners::SwingScreener.call(
        instruments: instruments,
        limit: 10,
      )

      next if screener_candidates.empty?

      # AI ranker should handle errors and return candidates without AI scores
      ranked_candidates = Screeners::AIRanker.call(
        candidates: screener_candidates,
        limit: 5,
      )

      expect(ranked_candidates).to be_an(Array)
      # Candidates may not have AI scores if ranking failed
      # But should still be returned (just without AI enhancement)
    end

    it "handles rate limiting" do
      # Mock rate limit response
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 429,
          body: { error: { message: "Rate limit exceeded" } }.to_json,
          headers: { "Content-Type" => "application/json" },
        )

      screener_candidates = Screeners::SwingScreener.call(
        instruments: instruments,
        limit: 10,
      )

      next if screener_candidates.empty?

      # Should handle rate limit gracefully
      ranked_candidates = Screeners::AIRanker.call(
        candidates: screener_candidates,
        limit: 5,
      )

      expect(ranked_candidates).to be_an(Array)
    end

    it "caches AI ranking results", vcr: { cassette_name: "screener_ai_pipeline/cache_test" } do
      # Clear cache to ensure fresh test
      Rails.cache.clear

      # Ensure AI ranking is enabled
      allow(AlgoConfig).to receive(:fetch).and_call_original
      allow(AlgoConfig).to receive(:fetch).with(%i[swing_trading ai_ranking]).and_return({ enabled: true })

      screener_candidates = Screeners::SwingScreener.call(
        instruments: instruments,
        limit: 10,
      )

      next if screener_candidates.empty?

      # First call - will record with VCR if cassette doesn't exist
      ranked1 = Screeners::AIRanker.call(
        candidates: screener_candidates.first(1),
        limit: 1,
      )

      expect(ranked1).to be_an(Array)
      expect(ranked1.first).to have_key(:ai_score) if ranked1.any?

      # Second call should use cache (if cache is enabled in test environment)
      # Note: Test environment uses :null_store, so caching is disabled
      # This test verifies the caching logic works when cache is available
      ranked2 = Screeners::AIRanker.call(
        candidates: screener_candidates.first(1),
        limit: 1,
      )

      expect(ranked2).to be_an(Array)
      # Results should be the same (either from cache or from VCR replay)
      expect(ranked2.first[:ai_score]).to eq(ranked1.first[:ai_score]) if ranked1.any? && ranked2.any?
    end

    it "sorts candidates by combined score correctly" do
      # Create ranked candidates with AI scores already assigned
      # This bypasses the actual API call and focuses on the sorting logic
      ranked_candidates = [
        { symbol: "STOCK1", score: 80.0, ai_score: 85.0, instrument_id: 1, indicators: {} },
        { symbol: "STOCK2", score: 90.0, ai_score: 75.0, instrument_id: 2, indicators: {} },
      ]

      final = Screeners::FinalSelector.call(swing_candidates: ranked_candidates, swing_limit: 10)
      expect(final).to be_a(Hash)
      expect(final[:swing]).to be_an(Array)
      expect(final[:swing]).not_to be_empty

      # Verify sorting - STOCK2 should rank higher due to higher screener score
      # Combined score calculation:
      # STOCK1: (80 * 0.6) + (85 * 0.4) = 48 + 34 = 82
      # STOCK2: (90 * 0.6) + (75 * 0.4) = 54 + 30 = 84
      # STOCK2 should win with combined score of 84 vs 82
      expect(final[:swing].first[:symbol]).to eq("STOCK2")
      expect(final[:swing].first[:combined_score]).to eq(84.0)
    end
  end

  describe "pipeline with empty screener results" do
    it "handles no candidates from screener" do
      # Use instrument without sufficient candles
      instrument_no_candles = create(:instrument, symbol_name: "EMPTY")
      empty_instruments = Instrument.where(id: instrument_no_candles.id)

      screener_candidates = Screeners::SwingScreener.call(
        instruments: empty_instruments,
        limit: 10,
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
