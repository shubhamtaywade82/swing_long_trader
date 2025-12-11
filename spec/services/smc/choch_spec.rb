# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SMC::CHOCH do
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

    context 'with bullish to bearish CHOCH' do
      it 'detects change from bullish to bearish structure' do
        candles = []
        base_price = 100.0

        # Create bullish structure (higher highs, higher lows)
        15.times do |i|
          price = base_price + (i * 1.0)
          candles << Candle.new(
            timestamp: (29 - i).days.ago,
            open: price,
            high: price + 2.0,
            low: price - 0.5,
            close: price + 1.5,
            volume: 1000
          )
        end

        # Transition to bearish structure (lower highs, lower lows)
        15.times do |i|
          price = 115.0 - (i * 1.0)
          candles << Candle.new(
            timestamp: (14 - i).days.ago,
            open: price,
            high: price + 0.5,
            low: price - 2.0,
            close: price - 1.5,
            volume: 1000
          )
        end

        result = described_class.detect(candles, lookback: 20)

        expect(result).not_to be_nil
        expect(result[:type]).to eq(:bearish)
        expect(result[:previous_structure]).to eq(:bullish)
        expect(result[:new_structure]).to eq(:bearish)
      end
    end

    context 'with bearish to bullish CHOCH' do
      it 'detects change from bearish to bullish structure' do
        candles = []
        base_price = 120.0

        # Create bearish structure (lower highs, lower lows)
        15.times do |i|
          price = base_price - (i * 1.0)
          candles << Candle.new(
            timestamp: (29 - i).days.ago,
            open: price,
            high: price + 0.5,
            low: price - 2.0,
            close: price - 1.5,
            volume: 1000
          )
        end

        # Transition to bullish structure (higher highs, higher lows)
        15.times do |i|
          price = 105.0 + (i * 1.0)
          candles << Candle.new(
            timestamp: (14 - i).days.ago,
            open: price,
            high: price + 2.0,
            low: price - 0.5,
            close: price + 1.5,
            volume: 1000
          )
        end

        result = described_class.detect(candles, lookback: 20)

        expect(result).not_to be_nil
        expect(result[:type]).to eq(:bullish)
        expect(result[:previous_structure]).to eq(:bearish)
        expect(result[:new_structure]).to eq(:bullish)
      end
    end

    context 'with no CHOCH' do
      it 'returns nil when structure remains the same' do
        candles = []
        base_price = 100.0

        # Create consistent bullish structure
        30.times do |i|
          price = base_price + (i * 0.5)
          candles << Candle.new(
            timestamp: (29 - i).days.ago,
            open: price,
            high: price + 2.0,
            low: price - 0.5,
            close: price + 1.5,
            volume: 1000
          )
        end

        result = described_class.detect(candles, lookback: 20)
        expect(result).to be_nil
      end
    end
  end
end

