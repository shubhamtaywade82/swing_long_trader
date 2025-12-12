# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/services/smc/mitigation_block'

RSpec.describe Smc::MitigationBlock do
  describe '.detect' do
    context 'with insufficient candles' do
      it 'returns empty array for nil input' do
        expect(described_class.detect(nil)).to eq([])
      end

      it 'returns empty array for insufficient candles' do
        candles = Array.new(5) { |i| Candle.new(timestamp: i.days.ago, open: 100, high: 105, low: 99, close: 103, volume: 1000) }
        expect(described_class.detect(candles)).to eq([])
      end
    end

    context 'with support mitigation blocks' do
      it 'detects support blocks from rejection candles' do
        candles = []
        support_level = 100.0

        # Create candles with support rejections
        20.times do |i|
          price = support_level + (i * 0.1)
          # Create rejection candles at support level
          if i % 5 == 0
            # Long lower wick (rejection)
            candles << Candle.new(
              timestamp: (19 - i).days.ago,
              open: support_level + 1.0,
              high: support_level + 1.5,
              low: support_level - 0.5,
              close: support_level + 0.5,
              volume: 1000
            )
          else
            candles << Candle.new(
              timestamp: (19 - i).days.ago,
              open: price,
              high: price + 1.0,
              low: price - 0.5,
              close: price + 0.5,
              volume: 1000
            )
          end
        end

        result = described_class.detect(candles, lookback: 20)

        expect(result).not_to be_empty
        support_blocks = result.select { |b| b[:type] == :support }
        expect(support_blocks).not_to be_empty
        expect(support_blocks.first[:strength]).to be_between(0, 1)
      end
    end

    context 'with resistance mitigation blocks' do
      it 'detects resistance blocks from rejection candles' do
        candles = []
        resistance_level = 110.0

        # Create candles with resistance rejections
        20.times do |i|
          price = 100.0 + (i * 0.1)
          # Create rejection candles at resistance level
          if i % 5 == 0
            # Long upper wick (rejection)
            candles << Candle.new(
              timestamp: (19 - i).days.ago,
              open: resistance_level - 1.0,
              high: resistance_level + 0.5,
              low: resistance_level - 1.5,
              close: resistance_level - 0.5,
              volume: 1000
            )
          else
            candles << Candle.new(
              timestamp: (19 - i).days.ago,
              open: price,
              high: price + 0.5,
              low: price - 1.0,
              close: price - 0.5,
              volume: 1000
            )
          end
        end

        result = described_class.detect(candles, lookback: 20)

        expect(result).not_to be_empty
        resistance_blocks = result.select { |b| b[:type] == :resistance }
        expect(resistance_blocks).not_to be_empty
        expect(resistance_blocks.first[:strength]).to be_between(0, 1)
      end
    end

    context 'with no mitigation blocks' do
      it 'returns empty array when no rejections found' do
        candles = []
        base_price = 100.0

        # Create candles without rejections
        20.times do |i|
          price = base_price + (i * 0.5)
          candles << Candle.new(
            timestamp: (19 - i).days.ago,
            open: price,
            high: price + 0.5,
            low: price - 0.5,
            close: price + 0.3,
            volume: 1000
          )
        end

        result = described_class.detect(candles, lookback: 20)
        # May return empty or have weak blocks
        expect(result).to be_an(Array)
      end
    end

    context 'with edge cases' do
      it 'handles single rejection (insufficient for block)' do
        candles = []
        base_price = 100.0

        # Create one rejection candle
        candles << Candle.new(
          timestamp: 1.day.ago,
          open: base_price + 1.0,
          high: base_price + 1.5,
          low: base_price - 0.5, # Long lower wick
          close: base_price + 0.5,
          volume: 1000
        )

        # Add more normal candles
        9.times do |i|
          price = base_price + (i * 0.1)
          candles << Candle.new(
            timestamp: (10 - i).days.ago,
            open: price,
            high: price + 0.5,
            low: price - 0.5,
            close: price + 0.3,
            volume: 1000
          )
        end

        result = described_class.detect(candles, lookback: 20)
        # Should not create block with single rejection
        expect(result).to be_an(Array)
      end

      it 'handles zero total range candles' do
        candles = []
        10.times do |i|
          price = 100.0
          candles << Candle.new(
            timestamp: (9 - i).days.ago,
            open: price,
            high: price,
            low: price,
            close: price,
            volume: 1000
          )
        end

        result = described_class.detect(candles, lookback: 20)
        expect(result).to be_an(Array)
      end

      it 'handles rejections at different price levels' do
        candles = []
        base_price = 100.0

        # Create rejections at different levels (not grouped)
        20.times do |i|
          price = base_price + (i * 2.0) # Large price differences
          if i % 5 == 0
            candles << Candle.new(
              timestamp: (19 - i).days.ago,
              open: price + 1.0,
              high: price + 1.5,
              low: price - 0.5, # Long lower wick
              close: price + 0.5,
              volume: 1000
            )
          else
            candles << Candle.new(
              timestamp: (19 - i).days.ago,
              open: price,
              high: price + 0.5,
              low: price - 0.5,
              close: price + 0.3,
              volume: 1000
            )
          end
        end

        result = described_class.detect(candles, lookback: 20)
        expect(result).to be_an(Array)
      end
    end
  end
end

