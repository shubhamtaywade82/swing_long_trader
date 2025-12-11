# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::IntradayFetcher do
  let(:instrument) { create(:instrument, symbol_name: 'TEST', security_id: '12345') }
  let(:mock_intraday_candles) do
    [
      {
        timestamp: 1.hour.ago.to_i,
        open: 100.0,
        high: 101.0,
        low: 99.0,
        close: 100.5,
        volume: 100_000
      },
      {
        timestamp: 2.hours.ago.to_i,
        open: 99.5,
        high: 100.5,
        low: 99.0,
        close: 100.0,
        volume: 90_000
      }
    ]
  end

  describe '.call' do
    context 'with valid instrument' do
      before do
        allow(instrument).to receive(:intraday_ohlc).and_return(mock_intraday_candles)
      end

      it 'fetches intraday candles without writing to database' do
        initial_count = CandleSeriesRecord.count

        result = described_class.call(
          instrument: instrument,
          interval: '15',
          days: 1
        )

        # Should not create any database records
        expect(CandleSeriesRecord.count).to eq(initial_count)
      end

      it 'returns candles in memory' do
        result = described_class.call(
          instrument: instrument,
          interval: '15',
          days: 1
        )

        expect(result).to be_a(Hash)
        expect(result[:candles]).to be_an(Array)
        expect(result[:candles].size).to eq(2)
      end

      it 'returns candles with correct structure' do
        result = described_class.call(
          instrument: instrument,
          interval: '15',
          days: 1
        )

        candle = result[:candles].first
        expect(candle).to have_key(:timestamp)
        expect(candle).to have_key(:open)
        expect(candle).to have_key(:high)
        expect(candle).to have_key(:low)
        expect(candle).to have_key(:close)
        expect(candle).to have_key(:volume)
      end

      it 'caches results' do
        # First call
        result1 = described_class.call(
          instrument: instrument,
          interval: '15',
          days: 1
        )

        # Second call should use cache
        result2 = described_class.call(
          instrument: instrument,
          interval: '15',
          days: 1
        )

        # Should return same data (from cache)
        expect(result2[:candles]).to eq(result1[:candles])
        # Should not call API twice
        expect(instrument).to have_received(:intraday_ohlc).once
      end

      it 'supports different intervals' do
        intervals = ['15', '30', '60', '120']

        intervals.each do |interval|
          result = described_class.call(
            instrument: instrument,
            interval: interval,
            days: 1
          )

          expect(result[:candles]).to be_an(Array)
        end
      end
    end

    context 'with caching' do
      before do
        allow(instrument).to receive(:intraday_ohlc).and_return(mock_intraday_candles)
        Rails.cache.clear
      end

      it 'uses cache key based on instrument and interval' do
        described_class.call(instrument: instrument, interval: '15', days: 1)
        described_class.call(instrument: instrument, interval: '30', days: 1)

        # Should call API for each different interval
        expect(instrument).to have_received(:intraday_ohlc).twice
      end

      it 'expires cache after TTL' do
        # Set short TTL for testing
        allow(described_class).to receive(:cache_ttl).and_return(1.second)

        described_class.call(instrument: instrument, interval: '15', days: 1)
        sleep(1.1)
        described_class.call(instrument: instrument, interval: '15', days: 1)

        # Should call API twice after cache expires
        expect(instrument).to have_received(:intraday_ohlc).twice
      end
    end

    context 'with API errors' do
      it 'handles API errors gracefully' do
        allow(instrument).to receive(:intraday_ohlc).and_raise(StandardError.new('API error'))

        result = described_class.call(
          instrument: instrument,
          interval: '15',
          days: 1
        )

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
        expect(result[:candles]).to eq([])
      end

      it 'does not write to database on error' do
        initial_count = CandleSeriesRecord.count
        allow(instrument).to receive(:intraday_ohlc).and_raise(StandardError.new('API error'))

        described_class.call(instrument: instrument, interval: '15', days: 1)

        expect(CandleSeriesRecord.count).to eq(initial_count)
      end
    end

    context 'with invalid parameters' do
      it 'handles missing instrument' do
        result = described_class.call(instrument: nil, interval: '15', days: 1)

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end

      it 'handles invalid interval' do
        result = described_class.call(
          instrument: instrument,
          interval: 'invalid',
          days: 1
        )

        # Should still attempt to fetch (API will handle validation)
        expect(result).to be_a(Hash)
      end
    end
  end
end

