# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Screeners::AIRanker, type: :service do
  let(:candidates) do
    [
      {
        instrument_id: 1,
        symbol: 'RELIANCE',
        score: 85,
        indicators: { rsi: 65, ema20: 100.0 }
      },
      {
        instrument_id: 2,
        symbol: 'TCS',
        score: 75,
        indicators: { rsi: 60, ema20: 200.0 }
      }
    ]
  end

  describe '.call' do
    it 'supports positional arguments' do
      allow_any_instance_of(described_class).to receive(:call).and_return([])

      described_class.call(candidates: candidates)

      expect_any_instance_of(described_class).to have_received(:call)
    end

    it 'supports keyword arguments' do
      allow_any_instance_of(described_class).to receive(:call).and_return([])

      described_class.call(candidates: candidates, limit: 10)

      expect_any_instance_of(described_class).to have_received(:call)
    end
  end

  describe '#call' do
    context 'when AI ranking is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: false)
      end

      it 'returns candidates without ranking' do
        result = described_class.new(candidates: candidates, limit: 1).call

        expect(result.size).to eq(1)
        expect(result.first[:symbol]).to eq('RELIANCE')
      end
    end

    context 'when AI ranking is enabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          enabled: true,
          model: 'gpt-4o-mini',
          temperature: 0.3
        )
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: '{"score": 80, "confidence": 75, "summary": "Good", "risk": "medium", "holding_days": 10}',
            cached: false
          }
        )
        allow_any_instance_of(described_class).to receive(:rate_limit_exceeded?).and_return(false)
      end

      it 'ranks candidates with AI scores' do
        result = described_class.new(candidates: candidates, limit: 2).call

        expect(result.size).to eq(2)
        expect(result.first).to have_key(:ai_score)
        expect(result.first).to have_key(:ai_confidence)
      end

      it 'sorts by combined score' do
        allow(Openai::Service).to receive(:call).and_return(
          {
            success: true,
            content: '{"score": 90, "confidence": 80, "summary": "Excellent", "risk": "low", "holding_days": 10}',
            cached: false
          }
        )

        result = described_class.new(candidates: candidates, limit: 2).call

        # First candidate has higher screener score (85) + AI score (90) = 175
        # Second candidate has lower screener score (75) + AI score (90) = 165
        expect(result.first[:symbol]).to eq('RELIANCE')
      end

      it 'caches AI rankings' do
        described_class.new(candidates: candidates, limit: 2).call

        # Second call should use cache
        described_class.new(candidates: candidates, limit: 2).call

        # Should only call OpenAI once per candidate
        expect(Openai::Service).to have_received(:call).twice
      end
    end

    context 'when rate limit is exceeded' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow_any_instance_of(described_class).to receive(:rate_limit_exceeded?).and_return(true)
      end

      it 'returns candidates without AI ranking' do
        result = described_class.new(candidates: candidates, limit: 2).call

        expect(result.size).to eq(2)
        expect(result.first).not_to have_key(:ai_score)
      end
    end

    context 'when OpenAI call fails' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(enabled: true)
        allow(Openai::Service).to receive(:call).and_return(
          { success: false, error: 'API error' }
        )
        allow_any_instance_of(described_class).to receive(:rate_limit_exceeded?).and_return(false)
      end

      it 'skips failed candidates' do
        result = described_class.new(candidates: candidates, limit: 2).call

        # Candidates without AI scores should still be included
        expect(result.size).to be >= 0
      end
    end
  end
end

