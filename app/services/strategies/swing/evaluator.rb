# frozen_string_literal: true

module Strategies
  module Swing
    class Evaluator < ApplicationService
      def self.call(candidate)
        new(candidate: candidate).call
      end

      def initialize(candidate:)
        @candidate = candidate
        @instrument = Instrument.find_by(id: candidate[:instrument_id])
      end

      def call
        return { success: false, error: "Invalid candidate" } if @candidate.blank?
        return { success: false, error: "Instrument not found" } if @instrument.blank?

        # Load candles
        daily_series = @instrument.load_daily_candles(limit: 100)
        return { success: false, error: "Failed to load daily candles" } unless daily_series&.candles&.any?

        weekly_series = @instrument.load_weekly_candles(limit: 52)

        # Run strategy engine
        Engine.call(
          instrument: @instrument,
          daily_series: daily_series,
          weekly_series: weekly_series,
        )
      end
    end
  end
end
