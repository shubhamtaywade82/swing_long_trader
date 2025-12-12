# frozen_string_literal: true

module Screeners
  class FinalSelector < ApplicationService
    DEFAULT_SWING_LIMIT = 10
    DEFAULT_LONGTERM_LIMIT = 5

    def self.call(swing_candidates: [], longterm_candidates: [], swing_limit: nil, longterm_limit: nil)
      new(
        swing_candidates: swing_candidates,
        longterm_candidates: longterm_candidates,
        swing_limit: swing_limit,
        longterm_limit: longterm_limit,
      ).call
    end

    def initialize(swing_candidates: [], longterm_candidates: [], swing_limit: nil, longterm_limit: nil)
      @swing_candidates = swing_candidates
      @longterm_candidates = longterm_candidates
      @swing_limit = swing_limit || DEFAULT_SWING_LIMIT
      @longterm_limit = longterm_limit || DEFAULT_LONGTERM_LIMIT
    end

    def call
      {
        swing: select_swing_candidates,
        longterm: select_longterm_candidates,
        summary: build_summary,
      }
    end

    private

    def select_swing_candidates
      return [] if @swing_candidates.empty?

      # Combine screener score and AI score (if available)
      ranked = @swing_candidates.map do |candidate|
        screener_score = candidate[:score] || 0
        ai_score = candidate[:ai_score] || 0
        combined_score = (screener_score * 0.6) + (ai_score * 0.4)

        candidate.merge(
          combined_score: combined_score.round(2),
          rank: nil, # Will be set after sorting
        )
      end

      # Sort by combined score
      sorted = ranked.sort_by { |c| -c[:combined_score] }.first(@swing_limit)
      sorted.each_with_index do |candidate, index|
        candidate[:rank] = index + 1
      end
      sorted
    end

    def select_longterm_candidates
      return [] if @longterm_candidates.empty?

      # For long-term, use screener score primarily (AI ranking optional)
      ranked = @longterm_candidates.map do |candidate|
        screener_score = candidate[:score] || 0
        ai_score = candidate[:ai_score] || 0
        # Long-term: 70% screener, 30% AI (if available)
        combined_score = ai_score.positive? ? (screener_score * 0.7) + (ai_score * 0.3) : screener_score

        candidate.merge(
          combined_score: combined_score.round(2),
          rank: nil,
        )
      end

      # Sort by combined score
      ranked.sort_by { |c| -c[:combined_score] }.first(@longterm_limit).each_with_index do |candidate, index|
        candidate[:rank] = index + 1
      end
    end

    def build_summary
      {
        swing_count: @swing_candidates.size,
        swing_selected: select_swing_candidates.size,
        longterm_count: @longterm_candidates.size,
        longterm_selected: select_longterm_candidates.size,
        timestamp: Time.current,
      }
    end
  end
end
