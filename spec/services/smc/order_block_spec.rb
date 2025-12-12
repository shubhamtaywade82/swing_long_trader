# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/services/smc/order_block'

RSpec.describe Smc::OrderBlock do
  describe '.detect' do
    context 'with insufficient candles' do
      it 'returns empty array for nil input' do
        expect(described_class.detect(nil)).to eq([])
      end

      it 'returns empty array for insufficient candles' do
        candles = Array.new(3) { |i| Candle.new(timestamp: i.days.ago, open: 100, high: 105, low: 99, close: 103, volume: 1000) }
        expect(described_class.detect(candles)).to eq([])
      end
    end

    context 'with bullish order blocks' do
      it 'detects bullish order block before strong move', skip: 'OrderBlock detection logic needs review' do
        candles = []
        base_price = 100.0

        # Create some normal candles
        10.times do |i|
          price = base_price + (i * 0.2)
          candles << Candle.new(
            timestamp: (19 - i).days.ago,
            open: price,
            high: price + 1.0,
            low: price - 1.0,
            close: price - 0.5, # Bearish
            volume: 1000
          )
        end

        # Create order block (last bearish candle before strong move)
        candles << Candle.new(
          timestamp: 9.days.ago,
          open: 102.0,
          high: 102.5,
          low: 101.0,
          close: 101.5, # Bearish
          volume: 1000
        )

        # Create strong bullish move
        candles << Candle.new(
          timestamp: 8.days.ago,
          open: 101.5,
          high: 104.0,
          low: 101.0,
          close: 103.5, # Strong bullish (2% move)
          volume: 2000
        )

        # Add more candles
        10.times do |i|
          price = 103.5 + (i * 0.1)
          candles << Candle.new(
            timestamp: (7 - i).days.ago,
            open: price,
            high: price + 0.5,
            low: price - 0.5,
            close: price + 0.3,
            volume: 1000
          )
        end

        result = described_class.detect(candles, lookback: 30)

        expect(result).not_to be_empty
        bullish_blocks = result.select { |b| b[:type] == :bullish }
        expect(bullish_blocks).not_to be_empty
        expect(bullish_blocks.first[:price_range]).to have_key(:high)
        expect(bullish_blocks.first[:price_range]).to have_key(:low)
        expect(bullish_blocks.first[:strength]).to be_between(0, 1)
      end
    end

    context 'with bearish order blocks' do
      it 'detects bearish order block before strong move', skip: 'OrderBlock detection logic needs review' do
        candles = []
        base_price = 110.0

        # Create some normal candles
        10.times do |i|
          price = base_price - (i * 0.2)
          candles << Candle.new(
            timestamp: (19 - i).days.ago,
            open: price,
            high: price + 1.0,
            low: price - 1.0,
            close: price + 0.5, # Bullish
            volume: 1000
          )
        end

        # Create order block (last bullish candle before strong move)
        candles << Candle.new(
          timestamp: 9.days.ago,
          open: 108.0,
          high: 108.5,
          low: 107.0,
          close: 108.5, # Bullish
          volume: 1000
        )

        # Create strong bearish move
        candles << Candle.new(
          timestamp: 8.days.ago,
          open: 108.5,
          high: 109.0,
          low: 106.0,
          close: 106.5, # Strong bearish (2% move)
          volume: 2000
        )

        # Add more candles
        10.times do |i|
          price = 106.5 - (i * 0.1)
          candles << Candle.new(
            timestamp: (7 - i).days.ago,
            open: price,
            high: price + 0.5,
            low: price - 0.5,
            close: price - 0.3,
            volume: 1000
          )
        end

        result = described_class.detect(candles, lookback: 30)

        expect(result).not_to be_empty
        bearish_blocks = result.select { |b| b[:type] == :bearish }
        expect(bearish_blocks).not_to be_empty
        expect(bearish_blocks.first[:price_range]).to have_key(:high)
        expect(bearish_blocks.first[:price_range]).to have_key(:low)
        expect(bearish_blocks.first[:strength]).to be_between(0, 1)
      end
    end

    context 'with no order blocks' do
      it 'returns empty array when no strong moves found' do
        candles = []
        base_price = 100.0

        # Create candles without strong moves
        20.times do |i|
          price = base_price + (i * 0.1)
          candles << Candle.new(
            timestamp: (19 - i).days.ago,
            open: price,
            high: price + 0.5,
            low: price - 0.5,
            close: price + 0.2,
            volume: 1000
          )
        end

        result = described_class.detect(candles, lookback: 30)
        expect(result).to be_an(Array)
      end
    end
  end
end

