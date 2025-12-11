# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/services/smc/bos'

RSpec.describe SMC::BOS do
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

        # Create uptrend with swing high
        30.times do |i|
          price = base_price + (i * 0.5)
          candles << Candle.new(
            timestamp: (29 - i).days.ago,
            open: price,
            high: price + 2.0,
            low: price - 1.0,
            close: price + 1.0,
            volume: 1000
          )
        end

        # Create swing high
        swing_high_price = 115.0
        candles << Candle.new(
          timestamp: 1.day.ago,
          open: 114.0,
          high: swing_high_price,
          low: 113.0,
          close: 114.5,
          volume: 1000
        )

        # Break above swing high
        candles << Candle.new(
          timestamp: Time.current,
          open: 115.5,
          high: 116.5,
          low: 115.0,
          close: 116.0,
          volume: 1000
        )

        result = described_class.detect(candles, lookback: 10)

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

        # Create downtrend with swing low
        30.times do |i|
          price = base_price - (i * 0.5)
          candles << Candle.new(
            timestamp: (29 - i).days.ago,
            open: price,
            high: price + 1.0,
            low: price - 2.0,
            close: price - 1.0,
            volume: 1000
          )
        end

        # Create swing low
        swing_low_price = 105.0
        candles << Candle.new(
          timestamp: 1.day.ago,
          open: 106.0,
          high: 107.0,
          low: swing_low_price,
          close: 106.5,
          volume: 1000
        )

        # Break below swing low
        candles << Candle.new(
          timestamp: Time.current,
          open: 104.5,
          high: 105.0,
          low: 103.5,
          close: 104.0,
          volume: 1000
        )

        result = described_class.detect(candles, lookback: 10)

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

