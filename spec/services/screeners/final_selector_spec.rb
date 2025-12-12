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
      before do
        # Call the service once for the basic test
        @result = described_class.call(
          swing_candidates: swing_candidates,
          longterm_candidates: longterm_candidates
        )
      end

      it 'returns selected candidates for both types' do
        expect(@result).to have_key(:swing)
        expect(@result).to have_key(:longterm)
        expect(@result).to have_key(:summary)
      end

      it 'selects top swing candidates by combined score' do
        # This test needs a different limit, so call separately
        result = described_class.call(
          swing_candidates: swing_candidates,
          swing_limit: 2
        )

        expect(result[:swing].size).to eq(2)
        expect(result[:swing].first[:symbol]).to eq('STOCK1')
        expect(result[:swing].first[:combined_score]).to be > result[:swing].last[:combined_score]
      end

      it 'calculates combined score correctly' do
        # This test needs limit: 1, so call separately
        result = described_class.call(
          swing_candidates: swing_candidates,
          swing_limit: 1
        )

        candidate = result[:swing].first
        expected_score = (85.0 * 0.6) + (80.0 * 0.4)
        expect(candidate[:combined_score]).to eq(expected_score.round(2))
      end

      it 'assigns ranks to selected candidates' do
        # This test needs limit: 3, so call separately
        result = described_class.call(
          swing_candidates: swing_candidates,
          swing_limit: 3
        )

        result[:swing].each_with_index do |candidate, index|
          expect(candidate[:rank]).to eq(index + 1)
        end
      end

      it 'selects top longterm candidates' do
        # This test needs longterm candidates only, so call separately
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

    context 'with longterm candidates and AI scores' do
      let(:longterm_with_ai) do
        [
          { symbol: 'STOCK4', score: 90.0, ai_score: 85.0 },
          { symbol: 'STOCK5', score: 88.0, ai_score: 80.0 }
        ]
      end

      it 'calculates combined score with 70% screener and 30% AI' do
        result = described_class.call(
          longterm_candidates: longterm_with_ai,
          longterm_limit: 1
        )

        candidate = result[:longterm].first
        expected_score = (90.0 * 0.7) + (85.0 * 0.3)
        expect(candidate[:combined_score]).to eq(expected_score.round(2))
      end
    end

    context 'with longterm candidates without AI scores' do
      it 'uses only screener score when AI score is missing' do
        result = described_class.call(
          longterm_candidates: longterm_candidates,
          longterm_limit: 1
        )

        candidate = result[:longterm].first
        expect(candidate[:combined_score]).to eq(90.0)
      end
    end

    context 'with more candidates than limit' do
      let(:many_candidates) do
        (1..20).map { |i| { symbol: "STOCK#{i}", score: 100.0 - i, ai_score: 90.0 - i } }
      end

      it 'selects only top candidates up to limit' do
        result = described_class.call(
          swing_candidates: many_candidates,
          swing_limit: 5
        )

        expect(result[:swing].size).to eq(5)
        expect(result[:swing].first[:symbol]).to eq('STOCK1')
        expect(result[:swing].last[:symbol]).to eq('STOCK5')
      end
    end

    context 'with candidates having nil scores' do
      let(:candidates_with_nil) do
        [
          { symbol: 'STOCK1', score: nil, ai_score: 80.0 },
          { symbol: 'STOCK2', score: 85.0, ai_score: nil }
        ]
      end

      it 'handles nil scores gracefully' do
        result = described_class.call(
          swing_candidates: candidates_with_nil,
          swing_limit: 2
        )

        expect(result[:swing].size).to eq(2)
        result[:swing].each do |candidate|
          expect(candidate[:combined_score]).to be_a(Numeric)
        end
      end
    end

    describe '#build_summary' do
      it 'includes correct counts in summary' do
        result = described_class.call(
          swing_candidates: swing_candidates,
          longterm_candidates: longterm_candidates,
          swing_limit: 2,
          longterm_limit: 1
        )

        expect(result[:summary][:swing_count]).to eq(3)
        expect(result[:summary][:swing_selected]).to eq(2)
        expect(result[:summary][:longterm_count]).to eq(2)
        expect(result[:summary][:longterm_selected]).to eq(1)
        expect(result[:summary][:timestamp]).to be_a(Time)
      end
    end
  end
end

