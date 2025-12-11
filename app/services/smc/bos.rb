# frozen_string_literal: true

module Smc
  # Break of Structure (BOS) Detection
  # BOS occurs when price breaks a previous swing high (bullish) or swing low (bearish)
  class Bos
    # Detect BOS in candle array
    # @param candles [Array<Candle>] Array of candles
    # @param lookback [Integer] Number of candles to look back for swing points (default: 20)
    # @return [Hash, nil] BOS information or nil if no BOS detected
    #   {
    #     type: :bullish/:bearish,
    #     index: Integer (candle index where BOS occurred),
    #     break_level: Float (price level that was broken),
    #     confirmation: Boolean (whether BOS is confirmed)
    #   }
    def self.detect(candles, lookback: 20)
      return nil if candles.nil? || candles.size < (lookback + 5)

      # Find swing highs and lows
      swing_highs = find_swing_highs(candles, lookback)
      swing_lows = find_swing_lows(candles, lookback)

      # Check for bullish BOS (break above previous swing high)
      bullish_bos = detect_bullish_bos(candles, swing_highs, lookback)
      return bullish_bos if bullish_bos

      # Check for bearish BOS (break below previous swing low)
      bearish_bos = detect_bearish_bos(candles, swing_lows, lookback)
      return bearish_bos if bearish_bos

      nil
    end

    private

    def self.find_swing_highs(candles, lookback)
      highs = []
      (lookback...candles.size - lookback).each do |i|
        is_swing_high = true
        # Check if current high is higher than surrounding candles
        (i - lookback..i + lookback).each do |j|
          next if j == i

          if candles[j].high >= candles[i].high
            is_swing_high = false
            break
          end
        end
        highs << { index: i, price: candles[i].high } if is_swing_high
      end
      highs
    end

    def self.find_swing_lows(candles, lookback)
      lows = []
      (lookback...candles.size - lookback).each do |i|
        is_swing_low = true
        # Check if current low is lower than surrounding candles
        (i - lookback..i + lookback).each do |j|
          next if j == i

          if candles[j].low <= candles[i].low
            is_swing_low = false
            break
          end
        end
        lows << { index: i, price: candles[i].low } if is_swing_low
      end
      lows
    end

    def self.detect_bullish_bos(candles, swing_highs, lookback)
      return nil if swing_highs.empty? || candles.size < 2

      latest_candle = candles.last
      previous_swing_highs = swing_highs.select { |sh| sh[:index] < candles.size - 1 }

      return nil if previous_swing_highs.empty?

      # Find the most recent swing high that hasn't been broken
      relevant_swing_high = previous_swing_highs.max_by { |sh| sh[:index] }
      return nil unless relevant_swing_high

      # Check if latest candle broke above the swing high
      if latest_candle.high > relevant_swing_high[:price]
        # Check for confirmation (close above break level)
        confirmation = latest_candle.close > relevant_swing_high[:price]

        {
          type: :bullish,
          index: candles.size - 1,
          break_level: relevant_swing_high[:price],
          confirmation: confirmation
        }
      end
    end

    def self.detect_bearish_bos(candles, swing_lows, lookback)
      return nil if swing_lows.empty? || candles.size < 2

      latest_candle = candles.last
      previous_swing_lows = swing_lows.select { |sl| sl[:index] < candles.size - 1 }

      return nil if previous_swing_lows.empty?

      # Find the most recent swing low that hasn't been broken
      relevant_swing_low = previous_swing_lows.max_by { |sl| sl[:index] }
      return nil unless relevant_swing_low

      # Check if latest candle broke below the swing low
      if latest_candle.low < relevant_swing_low[:price]
        # Check for confirmation (close below break level)
        confirmation = latest_candle.close < relevant_swing_low[:price]

        {
          type: :bearish,
          index: candles.size - 1,
          break_level: relevant_swing_low[:price],
          confirmation: confirmation
        }
      end
    end
  end
end

