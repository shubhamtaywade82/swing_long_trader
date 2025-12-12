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

  describe 'edge cases' do
    it 'handles normalise_candles with hash format missing arrays' do
      response = { 'high' => [105.0] }
      expect {
        series.normalise_candles(response)
      }.to raise_error(RuntimeError, /Unexpected candle format/)
    end

    it 'handles slice_candle with array format' do
      candle_array = [Time.current, 100.0, 105.0, 99.0, 103.0, 1_000_000]
      result = series.slice_candle(candle_array)

      expect(result[:timestamp]).to eq(Time.current)
      expect(result[:open]).to eq(100.0)
      expect(result[:high]).to eq(105.0)
      expect(result[:low]).to eq(99.0)
      expect(result[:close]).to eq(103.0)
      expect(result[:volume]).to eq(1_000_000)
    end

    it 'handles slice_candle with hash using string keys' do
      candle_hash = {
        'timestamp' => Time.current,
        'open' => 100.0,
        'high' => 105.0,
        'low' => 99.0,
        'close' => 103.0,
        'volume' => 1_000_000
      }
      result = series.slice_candle(candle_hash)

      expect(result[:open]).to eq(100.0)
      expect(result[:close]).to eq(103.0)
    end

    it 'handles slice_candle with hash using symbol keys' do
      candle_hash = {
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 103.0,
        volume: 1_000_000
      }
      result = series.slice_candle(candle_hash)

      expect(result[:open]).to eq(100.0)
      expect(result[:close]).to eq(103.0)
    end

    it 'handles slice_candle with missing volume' do
      candle_hash = {
        timestamp: Time.current,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        close: 103.0
      }
      result = series.slice_candle(candle_hash)

      expect(result[:volume]).to eq(0)
    end

    it 'handles slice_candle with unexpected format' do
      expect {
        series.slice_candle('invalid')
      }.to raise_error(RuntimeError, /Unexpected candle format/)
    end

    it 'handles slice_candle with array too short' do
      short_array = [Time.current, 100.0, 105.0] # Only 3 elements, need 6
      expect {
        series.slice_candle(short_array)
      }.to raise_error(RuntimeError, /Unexpected candle format/)
    end
  end

  describe 'accessor methods' do
    before do
      5.times do |i|
        series.add_candle(create(:candle,
          timestamp: i.days.ago,
          open: 100.0 + i,
          high: 105.0 + i,
          low: 99.0 + i,
          close: 103.0 + i,
          volume: 1_000_000 + i))
      end
    end

    it 'returns opens array' do
      expect(series.opens).to eq([104.0, 103.0, 102.0, 101.0, 100.0])
    end

    it 'returns closes array' do
      expect(series.closes).to eq([107.0, 106.0, 105.0, 104.0, 103.0])
    end

    it 'returns highs array' do
      expect(series.highs).to eq([109.0, 108.0, 107.0, 106.0, 105.0])
    end

    it 'returns lows array' do
      expect(series.lows).to eq([103.0, 102.0, 101.0, 100.0, 99.0])
    end

    it 'handles empty series' do
      empty_series = CandleSeries.new(symbol: 'TEST', interval: '1D')
      expect(empty_series.opens).to eq([])
      expect(empty_series.closes).to eq([])
      expect(empty_series.highs).to eq([])
      expect(empty_series.lows).to eq([])
    end
  end

  describe '#to_hash' do
    before do
      3.times do |i|
        series.add_candle(create(:candle,
          timestamp: i.days.ago,
          open: 100.0 + i,
          high: 105.0 + i,
          low: 99.0 + i,
          close: 103.0 + i,
          volume: 1_000_000 + i))
      end
    end

    it 'converts to hash format' do
      hash = series.to_hash

      expect(hash).to have_key('timestamp')
      expect(hash).to have_key('open')
      expect(hash).to have_key('high')
      expect(hash).to have_key('low')
      expect(hash).to have_key('close')
      expect(hash).to have_key('volume')
      expect(hash['timestamp'].size).to eq(3)
      expect(hash['open'].size).to eq(3)
    end
  end

  describe '#hlc' do
    before do
      3.times do |i|
        series.add_candle(create(:candle,
          timestamp: i.days.ago,
          open: 100.0 + i,
          high: 105.0 + i,
          low: 99.0 + i,
          close: 103.0 + i,
          volume: 1_000_000 + i))
      end
    end

    it 'returns high, low, close array' do
      hlc = series.hlc

      expect(hlc).to be_an(Array)
      expect(hlc.size).to eq(3)
      expect(hlc.first).to have_key(:date_time)
      expect(hlc.first).to have_key(:high)
      expect(hlc.first).to have_key(:low)
      expect(hlc.first).to have_key(:close)
    end

    it 'handles nil timestamp' do
      candle = create(:candle, timestamp: nil)
      series.add_candle(candle)

      hlc = series.hlc
      expect(hlc.last[:date_time]).to eq(Time.zone.at(0))
    end
  end
end

