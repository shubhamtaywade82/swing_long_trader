# frozen_string_literal: true

module Smc
  # Fair Value Gap (FVG) Detection
  # FVG is a gap between three candles where the middle candle doesn't overlap with the outer candles
  class FairValueGap
    # Detect fair value gaps in candle array
    # @param candles [Array<Candle>] Array of candles
    # @param lookback [Integer] Number of candles to analyze (default: 50)
    # @return [Array<Hash>] Array of fair value gaps
    #   Each gap: {
    #     type: :bullish/:bearish,
    #     index: Integer (middle candle index),
    #     gap_range: { high: Float, low: Float },
    #     filled: Boolean (whether gap has been filled)
    #   }
    def self.detect(candles, lookback: 50)
      return [] if candles.nil? || candles.size < 3

      gaps = []
      analyzed_range = candles.last([lookback, candles.size].min)

      # Check each set of three consecutive candles
      (0...analyzed_range.size - 2).each do |i|
        candle1 = analyzed_range[i]
        candle2 = analyzed_range[i + 1]
        candle3 = analyzed_range[i + 2]

        # Check for bullish FVG (gap up)
        bullish_gap = detect_bullish_fvg(candle1, candle2, candle3)
        if bullish_gap
          gaps << bullish_gap.merge(
            index: i + 1,
            filled: check_if_filled(candles, bullish_gap[:gap_range], i + 1)
          )
        end

        # Check for bearish FVG (gap down)
        bearish_gap = detect_bearish_fvg(candle1, candle2, candle3)
        if bearish_gap
          gaps << bearish_gap.merge(
            index: i + 1,
            filled: check_if_filled(candles, bearish_gap[:gap_range], i + 1)
          )
        end
      end

      gaps
    end

    private

    def self.detect_bullish_fvg(candle1, candle2, candle3)
      # Bullish FVG: candle3's low > candle1's high
      # And candle2 doesn't overlap with candle1 or candle3
      return nil unless candle3.low > candle1.high

      # Check that candle2 doesn't fill the gap
      candle2_high = [candle2.open, candle2.close].max
      candle2_low = [candle2.open, candle2.close].min

      return nil if candle2_high >= candle1.high || candle2_low <= candle3.low

      {
        type: :bullish,
        gap_range: {
          high: candle3.low,
          low: candle1.high
        }
      }
    end

    def self.detect_bearish_fvg(candle1, candle2, candle3)
      # Bearish FVG: candle3's high < candle1's low
      # And candle2 doesn't overlap with candle1 or candle3
      return nil unless candle3.high < candle1.low

      # Check that candle2 doesn't fill the gap
      candle2_high = [candle2.open, candle2.close].max
      candle2_low = [candle2.open, candle2.close].min

      return nil if candle2_low <= candle1.low || candle2_high >= candle3.high

      {
        type: :bearish,
        gap_range: {
          high: candle1.low,
          low: candle3.high
        }
      }
    end

    def self.check_if_filled(candles, gap_range, gap_index)
      # Check if any candle after the gap has filled it
      return false if gap_index >= candles.size - 1

      (gap_index + 1...candles.size).each do |i|
        candle = candles[i]
        # Gap is filled if candle's range overlaps with gap range
        if candle.low <= gap_range[:high] && candle.high >= gap_range[:low]
          return true
        end
      end

      false
    end
  end
end

