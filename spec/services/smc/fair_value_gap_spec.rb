# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SMC::FairValueGap do
  describe '.detect' do
    context 'with insufficient candles' do
      it 'returns empty array for nil input' do
        expect(described_class.detect(nil)).to eq([])
      end

      it 'returns empty array for insufficient candles' do
        candles = Array.new(2) { |i| Candle.new(timestamp: i.days.ago, open: 100, high: 105, low: 99, close: 103, volume: 1000) }
        expect(described_class.detect(candles)).to eq([])
      end
    end

    context 'with bullish fair value gaps' do
      it 'detects bullish FVG (gap up)' do
        candles = []
        base_price = 100.0

        # Create first candle
        candles << Candle.new(
          timestamp: 2.days.ago,
          open: base_price,
          high: base_price + 1.0,
          low: base_price - 0.5,
          close: base_price + 0.5,
          volume: 1000
        )

        # Create middle candle (doesn't fill gap)
        candles << Candle.new(
          timestamp: 1.day.ago,
          open: base_price + 0.5,
          high: base_price + 1.5,
          low: base_price + 0.3,
          close: base_price + 1.0,
          volume: 1000
        )

        # Create third candle (gap up)
        candles << Candle.new(
          timestamp: Time.current,
          open: base_price + 3.0,
          high: base_price + 4.0,
          low: base_price + 2.5,
          close: base_price + 3.5,
          volume: 1000
        )

        result = described_class.detect(candles, lookback: 50)

        expect(result).not_to be_empty
        bullish_gaps = result.select { |g| g[:type] == :bullish }
        expect(bullish_gaps).not_to be_empty
        expect(bullish_gaps.first[:gap_range]).to have_key(:high)
        expect(bullish_gaps.first[:gap_range]).to have_key(:low)
        expect(bullish_gaps.first[:filled]).to be false
      end
    end

    context 'with bearish fair value gaps' do
      it 'detects bearish FVG (gap down)' do
        candles = []
        base_price = 110.0

        # Create first candle
        candles << Candle.new(
          timestamp: 2.days.ago,
          open: base_price,
          high: base_price + 0.5,
          low: base_price - 1.0,
          close: base_price - 0.5,
          volume: 1000
        )

        # Create middle candle (doesn't fill gap)
        candles << Candle.new(
          timestamp: 1.day.ago,
          open: base_price - 0.5,
          high: base_price - 0.3,
          low: base_price - 1.5,
          close: base_price - 1.0,
          volume: 1000
        )

        # Create third candle (gap down)
        candles << Candle.new(
          timestamp: Time.current,
          open: base_price - 3.0,
          high: base_price - 2.5,
          low: base_price - 4.0,
          close: base_price - 3.5,
          volume: 1000
        )

        result = described_class.detect(candles, lookback: 50)

        expect(result).not_to be_empty
        bearish_gaps = result.select { |g| g[:type] == :bearish }
        expect(bearish_gaps).not_to be_empty
        expect(bearish_gaps.first[:gap_range]).to have_key(:high)
        expect(bearish_gaps.first[:gap_range]).to have_key(:low)
        expect(bearish_gaps.first[:filled]).to be false
      end
    end

    context 'with filled gaps' do
      it 'detects when FVG is filled' do
        candles = []
        base_price = 100.0

        # Create first candle
        candles << Candle.new(
          timestamp: 3.days.ago,
          open: base_price,
          high: base_price + 1.0,
          low: base_price - 0.5,
          close: base_price + 0.5,
          volume: 1000
        )

        # Create middle candle (gap)
        candles << Candle.new(
          timestamp: 2.days.ago,
          open: base_price + 0.5,
          high: base_price + 1.5,
          low: base_price + 0.3,
          close: base_price + 1.0,
          volume: 1000
        )

        # Create third candle (gap up)
        gap_low = base_price + 2.5
        gap_high = base_price + 3.0
        candles << Candle.new(
          timestamp: 1.day.ago,
          open: gap_high,
          high: base_price + 4.0,
          low: gap_low,
          close: base_price + 3.5,
          volume: 1000
        )

        # Create candle that fills the gap
        candles << Candle.new(
          timestamp: Time.current,
          open: base_price + 2.0,
          high: gap_high + 0.5,
          low: gap_low - 0.5,
          close: base_price + 2.5,
          volume: 1000
        )

        result = described_class.detect(candles, lookback: 50)

        expect(result).not_to be_empty
        filled_gaps = result.select { |g| g[:filled] == true }
        expect(filled_gaps).not_to be_empty
      end
    end

    context 'with no fair value gaps' do
      it 'returns empty array when no gaps found' do
        candles = []
        base_price = 100.0

        # Create overlapping candles (no gaps)
        10.times do |i|
          price = base_price + (i * 0.5)
          candles << Candle.new(
            timestamp: (9 - i).days.ago,
            open: price,
            high: price + 1.0,
            low: price - 1.0,
            close: price + 0.5,
            volume: 1000
          )
        end

        result = described_class.detect(candles, lookback: 50)
        expect(result).to be_an(Array)
      end
    end
  end
end

