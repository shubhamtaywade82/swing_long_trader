# frozen_string_literal: true

require "test_helper"

module Strategies
  module Swing
    class SignalBuilderTest < ActiveSupport::TestCase
      setup do
        @instrument = create(:instrument)
        @series = CandleSeries.new(symbol: @instrument.symbol_name, interval: "1D")

        # Create sample candles
        60.times do |i|
          @series.add_candle(
            Candle.new(
              timestamp: i.days.ago,
              open: 100.0 + i,
              high: 105.0 + i,
              low: 99.0 + i,
              close: 103.0 + i,
              volume: 1_000_000
            )
          )
        end
      end

      test "should validate inputs" do
        result = SignalBuilder.call(
          instrument: nil,
          daily_series: @series
        )

        assert_nil result
      end

      test "should require sufficient candles" do
        small_series = CandleSeries.new(symbol: @instrument.symbol_name, interval: "1D")
        small_series.add_candle(
          Candle.new(
            timestamp: 1.day.ago,
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1_000_000
          )
        )

        result = SignalBuilder.call(
          instrument: @instrument,
          daily_series: small_series
        )

        assert_nil result
      end
    end
  end
end

