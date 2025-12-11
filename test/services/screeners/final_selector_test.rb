# frozen_string_literal: true

require 'test_helper'

module Screeners
  class FinalSelectorTest < ActiveSupport::TestCase
    test 'should combine screener and AI scores for swing' do
      candidates = [
        { instrument_id: 1, symbol: 'STOCK1', score: 80.0, ai_score: 75.0 },
        { instrument_id: 2, symbol: 'STOCK2', score: 70.0, ai_score: 85.0 },
        { instrument_id: 3, symbol: 'STOCK3', score: 90.0, ai_score: 70.0 }
      ]

      result = FinalSelector.call(
        swing_candidates: candidates,
        swing_limit: 2
      )

      assert result[:swing].any?
      assert_equal 2, result[:swing].size
      # Should be sorted by combined score
      assert result[:swing].first[:combined_score] >= result[:swing].last[:combined_score]
    end

    test 'should handle candidates without AI scores' do
      candidates = [
        { instrument_id: 1, symbol: 'STOCK1', score: 80.0 },
        { instrument_id: 2, symbol: 'STOCK2', score: 70.0 }
      ]

      result = FinalSelector.call(
        swing_candidates: candidates,
        swing_limit: 2
      )

      assert result[:swing].any?
      # Should use screener score only when AI score missing
      assert result[:swing].first[:combined_score] > 0
    end

    test 'should select long-term candidates' do
      candidates = [
        { instrument_id: 1, symbol: 'STOCK1', score: 85.0, ai_score: 80.0 },
        { instrument_id: 2, symbol: 'STOCK2', score: 75.0, ai_score: 90.0 }
      ]

      result = FinalSelector.call(
        longterm_candidates: candidates,
        longterm_limit: 1
      )

      assert result[:longterm].any?
      assert_equal 1, result[:longterm].size
    end
  end
end


