# frozen_string_literal: true

require 'test_helper'

class CandlesIngestionTest < ActiveSupport::TestCase
  setup do
    @instrument = create(:instrument)
  end

  test 'daily ingestor should upsert candles' do
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
    @instrument.stub :historical_ohlc, mock_candles do
      result = Candles::DailyIngestor.call(
        instruments: Instrument.where(id: @instrument.id),
        days_back: 2
      )

      assert result[:success] > 0
      assert_equal 2, CandleSeriesRecord.where(instrument: @instrument, timeframe: '1D').count
    end
  end

  test 'weekly ingestor should aggregate daily to weekly' do
    # Create daily candles for a week
    7.times do |i|
      create(:daily_candle,
        instrument: @instrument,
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

    @instrument.stub :historical_ohlc, mock_daily do
      result = Candles::WeeklyIngestor.call(
        instruments: Instrument.where(id: @instrument.id),
        weeks_back: 1
      )

      assert result[:success] > 0
      # Should create at least 1 weekly candle
      assert CandleSeriesRecord.where(instrument: @instrument, timeframe: '1W').any?
    end
  end

  test 'intraday fetcher should not write to database' do
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

    @instrument.stub :intraday_ohlc, mock_intraday do
      result = Candles::IntradayFetcher.call(
        instrument: @instrument,
        interval: '15',
        days: 1
      )

      assert result[:success]
      assert result[:candles].any?
      # Verify no DB writes
      assert_equal initial_count, CandleSeriesRecord.count
    end
  end
end


