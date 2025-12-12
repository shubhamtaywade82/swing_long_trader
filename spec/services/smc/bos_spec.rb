# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/services/smc/bos'

RSpec.describe Smc::Bos do
  describe '.detect' do
    context 'with insufficient candles' do
      it 'returns nil for nil input' do
        expect(described_class.detect(nil)).to be_nil
      end

      it 'returns nil for empty array' do
        expect(described_class.detect([])).to be_nil
      end

      it 'returns nil for insufficient candles' do
        candles = Array.new(10) { |i| Candle.new(timestamp: i.days.ago, open: 100, high: 105, low: 99, close: 103, volume: 1000) }
        expect(described_class.detect(candles, lookback: 20)).to be_nil
      end
    end

    context 'with bullish BOS' do
      it 'detects bullish break of structure' do
        candles = []
        base_price = 100.0
        lookback = 10

        # Create enough candles so swing high falls within search range
        # Search range is (lookback...candles.size - lookback)
        # Need at least lookback + 5 candles, and swing high should be in middle range
        total_candles = 50
        swing_high_index = 25  # Place swing high in middle of search range

        # Create uptrend candles before swing high
        swing_high_index.times do |i|
          price = base_price + (i * 0.5)
          candles << Candle.new(
            timestamp: (swing_high_index - i).days.ago,
            open: price,
            high: price + 2.0,
            low: price - 1.0,
            close: price + 1.0,
            volume: 1000
          )
        end

        # Create swing high (must be highest in surrounding lookback candles)
        swing_high_price = base_price + (swing_high_index * 0.5) + 5.0  # Higher than surrounding
        candles << Candle.new(
          timestamp: 0.days.ago,
          open: swing_high_price - 1.0,
          high: swing_high_price,
          low: swing_high_price - 2.0,
          close: swing_high_price - 0.5,
          volume: 1000
        )

        # Create candles after swing high (lower highs to make it a swing high)
        (total_candles - swing_high_index - 1).times do |i|
          price = swing_high_price - 2.0 - (i * 0.3)  # Lower than swing high
          candles << Candle.new(
            timestamp: (i + 1).days.from_now,
            open: price,
            high: price + 1.5,  # Lower high than swing high
            low: price - 1.0,
            close: price + 0.5,
            volume: 1000
          )
        end

        # Break above swing high (last candle)
        break_candle = Candle.new(
          timestamp: (total_candles - swing_high_index).days.from_now,
          open: swing_high_price + 0.5,
          high: swing_high_price + 1.5,
          low: swing_high_price,
          close: swing_high_price + 1.0,
          volume: 1000
        )
        candles << break_candle

        result = described_class.detect(candles, lookback: lookback)

        expect(result).not_to be_nil
        expect(result[:type]).to eq(:bullish)
        expect(result[:break_level]).to be_within(0.1).of(swing_high_price)
        expect(result[:confirmation]).to be true
      end
    end

    context 'with bearish BOS' do
      it 'detects bearish break of structure' do
        candles = []
        base_price = 120.0
        lookback = 10

        # Create enough candles so swing low falls within search range
        total_candles = 50
        swing_low_index = 25  # Place swing low in middle of search range

        # Create downtrend candles before swing low
        swing_low_index.times do |i|
          price = base_price - (i * 0.5)
          candles << Candle.new(
            timestamp: (swing_low_index - i).days.ago,
            open: price,
            high: price + 1.0,
            low: price - 2.0,
            close: price - 1.0,
            volume: 1000
          )
        end

        # Create swing low (must be lowest in surrounding lookback candles)
        swing_low_price = base_price - (swing_low_index * 0.5) - 5.0  # Lower than surrounding
        candles << Candle.new(
          timestamp: 0.days.ago,
          open: swing_low_price + 1.0,
          high: swing_low_price + 2.0,
          low: swing_low_price,
          close: swing_low_price + 0.5,
          volume: 1000
        )

        # Create candles after swing low (higher lows to make it a swing low)
        (total_candles - swing_low_index - 1).times do |i|
          price = swing_low_price + 2.0 + (i * 0.3)  # Higher than swing low
          candles << Candle.new(
            timestamp: (i + 1).days.from_now,
            open: price,
            high: price + 1.0,
            low: price - 1.5,  # Higher low than swing low
            close: price - 0.5,
            volume: 1000
          )
        end

        # Break below swing low (last candle)
        break_candle = Candle.new(
          timestamp: (total_candles - swing_low_index).days.from_now,
          open: swing_low_price - 0.5,
          high: swing_low_price,
          low: swing_low_price - 1.5,
          close: swing_low_price - 1.0,
          volume: 1000
        )
        candles << break_candle

        result = described_class.detect(candles, lookback: lookback)

        expect(result).not_to be_nil
        expect(result[:type]).to eq(:bearish)
        expect(result[:break_level]).to be_within(0.1).of(swing_low_price)
        expect(result[:confirmation]).to be true
      end
    end

    context 'with no BOS' do
      it 'returns nil when no structure break occurs' do
        candles = []
        base_price = 100.0

        # Create sideways movement
        30.times do |i|
          price = base_price + (Math.sin(i * 0.1) * 2)
          candles << Candle.new(
            timestamp: (29 - i).days.ago,
            open: price,
            high: price + 1.0,
            low: price - 1.0,
            close: price + 0.5,
            volume: 1000
          )
        end

        result = described_class.detect(candles, lookback: 10)
        expect(result).to be_nil
      end
    end
  end
end

