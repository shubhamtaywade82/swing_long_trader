# frozen_string_literal: true

module Smc
  # Order Block Detection
  # Order blocks are the last opposing candle before a strong move, indicating institutional orders
  class OrderBlock
    # Detect order blocks in candle array
    # @param candles [Array<Candle>] Array of candles
    # @param lookback [Integer] Number of candles to analyze (default: 30)
    # @return [Array<Hash>] Array of order blocks
    #   Each block: {
    #     type: :bullish/:bearish,
    #     index: Integer (candle index),
    #     price_range: { high: Float, low: Float },
    #     strength: Float (0-1)
    #   }
    def self.detect(candles, lookback: 30)
      return [] if candles.nil? || candles.size < 5

      blocks = []
      analyzed_range = candles.last([lookback, candles.size].min)

      # Find strong moves (momentum candles)
      strong_moves = find_strong_moves(analyzed_range)

      # For each strong move, find the order block (last opposing candle)
      strong_moves.each do |move|
        block = find_order_block_for_move(analyzed_range, move)
        blocks << block if block
      end

      blocks.uniq { |b| b[:index] } # Remove duplicates
    end

    private

    def self.find_strong_moves(candles)
      moves = []
      min_body_ratio = 0.6 # At least 60% of candle is body
      min_move_pct = 1.5 # At least 1.5% move

      candles.each_with_index do |candle, idx|
        next if idx.zero?

        body_size = (candle.close - candle.open).abs
        total_range = candle.high - candle.low
        next if total_range.zero?

        body_ratio = body_size / total_range
        move_pct = (body_size / candle.open) * 100

        if body_ratio >= min_body_ratio && move_pct >= min_move_pct
          type = candle.close > candle.open ? :bullish : :bearish
          moves << {
            index: idx,
            type: type,
            body_size: body_size,
            move_pct: move_pct
          }
        end
      end

      moves
    end

    def self.find_order_block_for_move(candles, move)
      move_idx = move[:index]
      return nil if move_idx.zero?

      # Look back from the strong move to find the last opposing candle
      (move_idx - 1).downto(0) do |i|
        candle = candles[i]

        # Check if this is an opposing candle (opposite direction)
        is_opposing = if move[:type] == :bullish
                        candle.close < candle.open # Bearish candle
                      else
                        candle.close > candle.open # Bullish candle
                      end

        if is_opposing
          # Check if this candle has significant body (potential order block)
          body_size = (candle.close - candle.open).abs
          total_range = candle.high - candle.low
          next if total_range.zero?

          body_ratio = body_size / total_range

          # Order block should have decent body (at least 40%)
          if body_ratio >= 0.4
            strength = calculate_strength(candle, move)

            return {
              type: move[:type] == :bullish ? :bullish : :bearish,
              index: i,
              price_range: {
                high: candle.high,
                low: candle.low
              },
              strength: strength,
              move_index: move_idx
            }
          end
        end

        # Stop looking if we encounter a candle in the same direction as the move
        break if (move[:type] == :bullish && candle.close > candle.open) ||
                 (move[:type] == :bearish && candle.close < candle.open)
      end

      nil
    end

    def self.calculate_strength(candle, move)
      # Strength based on:
      # 1. Body size of order block
      # 2. Strength of the subsequent move
      body_size = (candle.close - candle.open).abs
      total_range = candle.high - candle.low
      body_ratio = total_range.zero? ? 0 : body_size / total_range

      move_strength = [move[:move_pct] / 5.0, 1.0].min # Normalize move strength

      (body_ratio * 0.5 + move_strength * 0.5).round(2)
    end
  end
end

