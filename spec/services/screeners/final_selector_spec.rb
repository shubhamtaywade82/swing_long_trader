# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Screeners::FinalSelector do
  describe '.call' do
    let(:swing_candidates) do
      [
        { symbol: 'STOCK1', score: 85.0, ai_score: 80.0 },
        { symbol: 'STOCK2', score: 82.0, ai_score: 75.0 },
        { symbol: 'STOCK3', score: 80.0, ai_score: 70.0 }
      ]
    end

    let(:longterm_candidates) do
      [
        { symbol: 'STOCK4', score: 90.0 },
        { symbol: 'STOCK5', score: 88.0 }
      ]
    end

    context 'with swing and longterm candidates' do
      it 'returns selected candidates for both types' do
        result = described_class.call(
          swing_candidates: swing_candidates,
          longterm_candidates: longterm_candidates
        )

        expect(result).to have_key(:swing)
        expect(result).to have_key(:longterm)
        expect(result).to have_key(:summary)
      end

      it 'selects top swing candidates by combined score' do
        result = described_class.call(
          swing_candidates: swing_candidates,
          swing_limit: 2
        )

        expect(result[:swing].size).to eq(2)
        expect(result[:swing].first[:symbol]).to eq('STOCK1')
        expect(result[:swing].first[:combined_score]).to be > result[:swing].last[:combined_score]
      end

      it 'calculates combined score correctly' do
        result = described_class.call(
          swing_candidates: swing_candidates,
          swing_limit: 1
        )

        candidate = result[:swing].first
        expected_score = (85.0 * 0.6) + (80.0 * 0.4)
        expect(candidate[:combined_score]).to eq(expected_score.round(2))
      end

      it 'assigns ranks to selected candidates' do
        result = described_class.call(
          swing_candidates: swing_candidates,
          swing_limit: 3
        )

        result[:swing].each_with_index do |candidate, index|
          expect(candidate[:rank]).to eq(index + 1)
        end
      end

      it 'selects top longterm candidates' do
        result = described_class.call(
          longterm_candidates: longterm_candidates,
          longterm_limit: 2
        )

        expect(result[:longterm].size).to eq(2)
        expect(result[:longterm].first[:score]).to be >= result[:longterm].last[:score]
      end
    end

    context 'with empty candidates' do
      it 'returns empty arrays when no candidates provided' do
        result = described_class.call(
          swing_candidates: [],
          longterm_candidates: []
        )

        expect(result[:swing]).to be_empty
        expect(result[:longterm]).to be_empty
      end
    end

    context 'with custom limits' do
      it 'respects custom swing limit' do
        result = described_class.call(
          swing_candidates: swing_candidates,
          swing_limit: 1
        )

        expect(result[:swing].size).to eq(1)
      end

      it 'respects custom longterm limit' do
        result = described_class.call(
          longterm_candidates: longterm_candidates,
          longterm_limit: 1
        )

        expect(result[:longterm].size).to eq(1)
      end
    end

    context 'with candidates without AI scores' do
      let(:candidates_no_ai) do
        [
          { symbol: 'STOCK1', score: 85.0 },
          { symbol: 'STOCK2', score: 82.0 }
        ]
      end

      it 'handles missing AI scores gracefully' do
        result = described_class.call(
          swing_candidates: candidates_no_ai,
          swing_limit: 2
        )

        expect(result[:swing].size).to eq(2)
        result[:swing].each do |candidate|
          expect(candidate[:combined_score]).to be_a(Numeric)
        end
      end

      it 'uses 0 for missing AI scores in calculation' do
        result = described_class.call(
          swing_candidates: candidates_no_ai,
          swing_limit: 1
        )

        candidate = result[:swing].first
        expected_score = (85.0 * 0.6) + (0.0 * 0.4)
        expect(candidate[:combined_score]).to eq(expected_score.round(2))
      end
    end
  end
end

