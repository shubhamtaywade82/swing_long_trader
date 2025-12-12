# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandleSeries, type: :model do
  let(:series) { CandleSeries.new(symbol: 'TEST', interval: '1D') }

  describe 'initialization' do
    it 'creates a series with symbol and interval' do
      expect(series.symbol).to eq('TEST')
      expect(series.interval).to eq('1D')
      expect(series.candles).to eq([])
    end

    it 'uses default interval if not provided' do
      series = CandleSeries.new(symbol: 'TEST')
      expect(series.interval).to eq('5')
    end
  end

  describe '#add_candle' do
    it 'adds a candle to the series' do
      candle = Candle.new(
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 103.0,
        volume: 1_000_000
      )

      series.add_candle(candle)

      expect(series.candles.size).to eq(1)
      expect(series.candles.first).to eq(candle)
    end
  end

  describe '#each' do
    it 'iterates over candles' do
      candle1 = Candle.new(timestamp: Time.current, open: 100, high: 105, low: 99, close: 103, volume: 1000)
      candle2 = Candle.new(timestamp: Time.current, open: 103, high: 108, low: 102, close: 106, volume: 1000)

      series.add_candle(candle1)
      series.add_candle(candle2)

      candles = []
      series.each { |c| candles << c }

      expect(candles.size).to eq(2)
      expect(candles).to include(candle1, candle2)
    end
  end

  describe '#load_from_raw' do
    it 'loads candles from raw response array' do
      raw_response = [
        {
          timestamp: Time.current,
          open: 100.0,
          high: 105.0,
          low: 99.0,
          close: 103.0,
          volume: 1_000_000
        },
        {
          timestamp: Time.current + 1.day,
          open: 103.0,
          high: 108.0,
          low: 102.0,
          close: 106.0,
          volume: 1_100_000
        }
      ]

      series.load_from_raw(raw_response)

      expect(series.candles.size).to eq(2)
      expect(series.candles.first.close).to eq(103.0)
      expect(series.candles.last.close).to eq(106.0)
    end

    it 'handles hash format with arrays' do
      raw_response = {
        'timestamp' => [Time.current.to_i, (Time.current + 1.day).to_i],
        'open' => [100.0, 103.0],
        'high' => [105.0, 108.0],
        'low' => [99.0, 102.0],
        'close' => [103.0, 106.0],
        'volume' => [1_000_000, 1_100_000]
      }

      series.load_from_raw(raw_response)

      expect(series.candles.size).to eq(2)
      expect(series.candles.first.close).to eq(103.0)
      expect(series.candles.last.close).to eq(106.0)
    end
  end

  describe '#normalise_candles' do
    it 'returns empty array for blank response' do
      expect(series.normalise_candles(nil)).to eq([])
      expect(series.normalise_candles([])).to eq([])
    end

    it 'handles array format' do
      response = [
        { timestamp: Time.current, open: 100, high: 105, low: 99, close: 103, volume: 1000 }
      ]

      result = series.normalise_candles(response)
      expect(result).to be_an(Array)
      expect(result.first[:close]).to eq(103)
    end
  end
end

