# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Candles Ingestion', type: :integration do
  let(:instrument) { create(:instrument) }

  describe 'daily ingestor' do
    it 'upserts candles' do
      # Mock DhanHQ API response
      mock_candles = [
        {
          timestamp: 1.day.ago.to_i,
          open: 100.0,
          high: 105.0,
          low: 99.0,
          close: 103.0,
          volume: 1_000_000
        },
        {
          timestamp: 2.days.ago.to_i,
          open: 98.0,
          high: 102.0,
          low: 97.0,
          close: 100.0,
          volume: 900_000
        }
      ]

      # Stub the historical_ohlc method
      allow(instrument).to receive(:historical_ohlc).and_return(mock_candles)

      result = Candles::DailyIngestor.call(
        instruments: Instrument.where(id: instrument.id),
        days_back: 2
      )

      expect(result[:success]).to be > 0
      expect(CandleSeriesRecord.where(instrument: instrument, timeframe: '1D').count).to eq(2)
    end
  end

  describe 'weekly ingestor' do
    it 'aggregates daily to weekly' do
      # Create daily candles for a week
      7.times do |i|
        create(:daily_candle,
          instrument: instrument,
          timestamp: i.days.ago,
          open: 100.0 + i,
          high: 105.0 + i,
          low: 99.0 + i,
          close: 103.0 + i,
          volume: 1_000_000
        )
      end

      # Mock daily candles API response
      mock_daily = 7.times.map do |i|
        {
          timestamp: i.days.ago.to_i,
          open: 100.0 + i,
          high: 105.0 + i,
          low: 99.0 + i,
          close: 103.0 + i,
          volume: 1_000_000
        }
      end

      allow(instrument).to receive(:historical_ohlc).and_return(mock_daily)

      result = Candles::WeeklyIngestor.call(
        instruments: Instrument.where(id: instrument.id),
        weeks_back: 1
      )

      expect(result[:success]).to be > 0
      # Should create at least 1 weekly candle
      expect(CandleSeriesRecord.where(instrument: instrument, timeframe: '1W')).to be_any
    end
  end

  describe 'intraday fetcher' do
    it 'should not write to database' do
      initial_count = CandleSeriesRecord.count

      # Mock intraday API response
      mock_intraday = [
        {
          timestamp: 1.hour.ago.to_i,
          open: 100.0,
          high: 105.0,
          low: 99.0,
          close: 103.0,
          volume: 100_000
        }
      ]

      allow(instrument).to receive(:intraday_ohlc).and_return(mock_intraday)

      result = Candles::IntradayFetcher.call(
        instrument: instrument,
        interval: '15',
        days: 1
      )

      expect(result[:success]).to be true
      expect(result[:candles]).to be_any
      # Verify no DB writes
      expect(CandleSeriesRecord.count).to eq(initial_count)
    end
  end
end

