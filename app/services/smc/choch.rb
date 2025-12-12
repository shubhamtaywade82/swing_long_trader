# frozen_string_literal: true

module Smc
  # Change of Character (CHOCH) Detection
  # CHOCH occurs when market structure changes from bullish to bearish or vice versa
  class Choch
    # Detect CHOCH in candle array
    # @param candles [Array<Candle>] Array of candles
    # @param lookback [Integer] Number of candles to analyze (default: 20)
    # @return [Hash, nil] CHOCH information or nil if no CHOCH detected
    #   {
    #     type: :bullish/:bearish,
    #     index: Integer (candle index where CHOCH occurred),
    #     previous_structure: :bullish/:bearish,
    #     new_structure: :bullish/:bearish
    #   }
    def self.detect(candles, lookback: 20)
      return nil if candles.nil? || candles.size < (lookback + 5)

      # Determine current market structure
      current_structure = determine_structure(candles, lookback)
      return nil unless current_structure

      # Determine previous market structure
      previous_candles = candles[0..-2]
      previous_structure = determine_structure(previous_candles, lookback)

      # Check if structure changed
      return unless previous_structure && current_structure != previous_structure

      {
        type: current_structure,
        index: candles.size - 1,
        previous_structure: previous_structure,
        new_structure: current_structure,
      }
    end

    def self.determine_structure(candles, lookback)
      return nil if candles.size < lookback

      # Analyze recent candles to determine structure
      recent_candles = candles.last(lookback)

      # Count higher highs and higher lows (bullish structure)
      higher_highs = 0
      higher_lows = 0
      lower_highs = 0
      lower_lows = 0

      (1...recent_candles.size).each do |i|
        if recent_candles[i].high > recent_candles[i - 1].high
          higher_highs += 1
        elsif recent_candles[i].high < recent_candles[i - 1].high
          lower_highs += 1
        end

        if recent_candles[i].low > recent_candles[i - 1].low
          higher_lows += 1
        elsif recent_candles[i].low < recent_candles[i - 1].low
          lower_lows += 1
        end
      end

      # Determine structure based on majority
      bullish_signals = higher_highs + higher_lows
      bearish_signals = lower_highs + lower_lows

      if bullish_signals > bearish_signals
        :bullish
      elsif bearish_signals > bullish_signals
        :bearish
      else
        nil # Sideways/indecisive
      end
    end
  end
end
