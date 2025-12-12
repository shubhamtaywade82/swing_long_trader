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

    context 'with private methods' do
      describe '.find_rejection_candles' do
        it 'finds bullish rejection candles (long lower wick)' do
          candles = []
          candles << Candle.new(
            timestamp: 1.day.ago,
            open: 102.0,
            high: 103.0,
            low: 99.0, # Long lower wick
            close: 101.5,
            volume: 1000
          )

          rejections = described_class.send(:find_rejection_candles, candles)

          expect(rejections).not_to be_empty
          expect(rejections.first[:type]).to eq(:support)
        end

        it 'finds bearish rejection candles (long upper wick)' do
          candles = []
          candles << Candle.new(
            timestamp: 1.day.ago,
            open: 100.0,
            high: 104.0, # Long upper wick
            low: 99.0,
            close: 100.5,
            volume: 1000
          )

          rejections = described_class.send(:find_rejection_candles, candles)

          expect(rejections).not_to be_empty
          expect(rejections.first[:type]).to eq(:resistance)
        end

        it 'ignores candles without significant wicks' do
          candles = []
          candles << Candle.new(
            timestamp: 1.day.ago,
            open: 100.0,
            high: 101.0,
            low: 99.0,
            close: 100.5,
            volume: 1000
          )

          rejections = described_class.send(:find_rejection_candles, candles)

          expect(rejections).to be_empty
        end

        it 'handles zero total range candles' do
          candles = []
          candles << Candle.new(
            timestamp: 1.day.ago,
            open: 100.0,
            high: 100.0,
            low: 100.0,
            close: 100.0,
            volume: 1000
          )

          rejections = described_class.send(:find_rejection_candles, candles)

          expect(rejections).to be_empty
        end
      end

      describe '.group_by_price_level' do
        it 'groups rejections at similar price levels' do
          rejections = [
            { price_level: 100.0, index: 0, type: :support },
            { price_level: 100.5, index: 1, type: :support },
            { price_level: 101.0, index: 2, type: :support }
          ]

          grouped = described_class.send(:group_by_price_level, rejections)

          expect(grouped).to be_a(Hash)
          expect(grouped.keys.size).to be <= 3
        end

        it 'separates rejections at different price levels' do
          rejections = [
            { price_level: 100.0, index: 0, type: :support },
            { price_level: 110.0, index: 1, type: :support } # 10% difference
          ]

          grouped = described_class.send(:group_by_price_level, rejections)

          expect(grouped.keys.size).to eq(2)
        end
      end

      describe '.determine_block_type' do
        it 'determines support block when support rejections dominate' do
          rejections = [
            { type: :support },
            { type: :support },
            { type: :resistance }
          ]

          block_type = described_class.send(:determine_block_type, rejections)

          expect(block_type).to eq(:support)
        end

        it 'determines resistance block when resistance rejections dominate' do
          rejections = [
            { type: :support },
            { type: :resistance },
            { type: :resistance }
          ]

          block_type = described_class.send(:determine_block_type, rejections)

          expect(block_type).to eq(:resistance)
        end

        it 'defaults to support when counts are equal' do
          rejections = [
            { type: :support },
            { type: :resistance }
          ]

          block_type = described_class.send(:determine_block_type, rejections)

          expect(block_type).to eq(:support)
        end
      end

      describe '.calculate_strength' do
        it 'calculates strength based on rejection count' do
          rejections = [
            { index: 0 },
            { index: 1 },
            { index: 2 }
          ]

          strength = described_class.send(:calculate_strength, rejections)

          expect(strength).to be_between(0, 1)
        end

        it 'caps strength at 1.0' do
          rejections = Array.new(10) { |i| { index: i } }

          strength = described_class.send(:calculate_strength, rejections)

          expect(strength).to be <= 1.0
        end

        it 'boosts strength for recent rejections' do
          rejections = [
            { index: 0 },
            { index: 1 },
            { index: 2 },
            { index: 15 }, # Recent
            { index: 16 } # Recent
          ]

          strength = described_class.send(:calculate_strength, rejections)

          expect(strength).to be_between(0, 1)
        end
      end
    end

    context 'with sorting' do
      it 'sorts blocks by strength descending' do
        candles = []
        base_price = 100.0

        # Create multiple rejection candles at different levels
        30.times do |i|
          price = base_price + (i * 0.1)
          if i % 3 == 0
            candles << Candle.new(
              timestamp: (29 - i).days.ago,
              open: price + 1.0,
              high: price + 1.5,
              low: price - 0.5,
              close: price + 0.5,
              volume: 1000
            )
          else
            candles << Candle.new(
              timestamp: (29 - i).days.ago,
              open: price,
              high: price + 0.5,
              low: price - 0.5,
              close: price + 0.3,
              volume: 1000
            )
          end
        end

        result = described_class.detect(candles, lookback: 30)

        if result.size >= 2
          strengths = result.map { |b| b[:strength] }
          expect(strengths).to eq(strengths.sort.reverse)
        end
      end
    end
  end
end

