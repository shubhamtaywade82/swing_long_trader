# frozen_string_literal: true

module Smc
  # Mitigation Block Detection
  # Mitigation blocks are areas where price previously rejected, indicating potential support/resistance
  class MitigationBlock
    # Detect mitigation blocks in candle array
    # @param candles [Array<Candle>] Array of candles
    # @param lookback [Integer] Number of candles to look back (default: 50)
    # @return [Array<Hash>] Array of mitigation blocks
    #   Each block: {
    #     type: :support/:resistance,
    #     index: Integer (candle index),
    #     price_level: Float (key price level),
    #     strength: Float (0-1, based on rejections)
    #   }
    def self.detect(candles, lookback: 50)
      return [] if candles.nil? || candles.size < 10

      blocks = []
      analyzed_range = candles.last([lookback, candles.size].min)

      # Find rejection candles (long wicks)
      rejection_candles = find_rejection_candles(analyzed_range)

      # Group rejections by price level
      grouped_rejections = group_by_price_level(rejection_candles)

      # Identify significant blocks (multiple rejections at similar levels)
      grouped_rejections.each do |level, rejections|
        next if rejections.size < 2 # Need at least 2 rejections

        block_type = determine_block_type(rejections)
        strength = calculate_strength(rejections)

        blocks << {
          type: block_type,
          index: rejections.last[:index],
          price_level: level,
          strength: strength,
          rejection_count: rejections.size
        }
      end

      blocks.sort_by { |b| -b[:strength] } # Sort by strength (strongest first)
    end

    private

    def self.find_rejection_candles(candles)
      rejections = []
      wick_ratio_threshold = 0.3 # At least 30% of candle is wick

      candles.each_with_index do |candle, idx|
        body_size = (candle.close - candle.open).abs
        total_range = candle.high - candle.low
        next if total_range.zero?

        upper_wick = candle.high - [candle.open, candle.close].max
        lower_wick = [candle.open, candle.close].min - candle.low

        # Bullish rejection (long lower wick)
        if lower_wick / total_range >= wick_ratio_threshold && body_size / total_range < 0.5
          rejections << {
            index: idx,
            type: :support,
            price_level: candle.low,
            wick_size: lower_wick
          }
        end

        # Bearish rejection (long upper wick)
        if upper_wick / total_range >= wick_ratio_threshold && body_size / total_range < 0.5
          rejections << {
            index: idx,
            type: :resistance,
            price_level: candle.high,
            wick_size: upper_wick
          }
        end
      end

      rejections
    end

    def self.group_by_price_level(rejections)
      grouped = {}
      price_tolerance = 0.01 # 1% tolerance for grouping

      rejections.each do |rejection|
        # Find existing group within tolerance
        existing_level = grouped.keys.find do |level|
          (rejection[:price_level] - level).abs / level <= price_tolerance
        end

        if existing_level
          grouped[existing_level] << rejection
        else
          grouped[rejection[:price_level]] = [rejection]
        end
      end

      grouped
    end

    def self.determine_block_type(rejections)
      support_count = rejections.count { |r| r[:type] == :support }
      resistance_count = rejections.count { |r| r[:type] == :resistance }

      support_count >= resistance_count ? :support : :resistance
    end

    def self.calculate_strength(rejections)
      # Strength based on number of rejections and recency
      base_strength = [rejections.size / 5.0, 1.0].min # Max 1.0 for 5+ rejections

      # Boost strength if rejections are recent
      recent_rejections = rejections.count { |r| r[:index] >= rejections.map { |x| x[:index] }.max - 10 }
      recency_boost = recent_rejections * 0.1

      [base_strength + recency_boost, 1.0].min
    end
  end
end

