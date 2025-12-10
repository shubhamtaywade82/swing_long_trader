# frozen_string_literal: true

require 'test_helper'

module Candles
  class IngestorTest < ActiveSupport::TestCase
    setup do
      @instrument = create(:instrument)
    end

    test 'should upsert candles successfully' do
      candles_data = [
        {
          timestamp: 1.day.ago,
          open: 100.0,
          high: 105.0,
          low: 99.0,
          close: 103.0,
          volume: 1_000_000
        },
        {
          timestamp: 2.days.ago,
          open: 98.0,
          high: 102.0,
          low: 97.0,
          close: 100.0,
          volume: 900_000
        }
      ]

      result = Ingestor.upsert_candles(
        instrument: @instrument,
        timeframe: '1D',
        candles_data: candles_data
      )

      assert result[:success]
      assert_equal 2, result[:upserted]
      assert_equal 2, CandleSeriesRecord.count
    end

    test 'should skip duplicate candles' do
      # Create existing candle
      create(:daily_candle, instrument: @instrument, timestamp: 1.day.ago, close: 100.0)

      candles_data = [
        {
          timestamp: 1.day.ago,
          open: 100.0,
          high: 105.0,
          low: 99.0,
          close: 100.0, # Same as existing
          volume: 1_000_000
        }
      ]

      result = Ingestor.upsert_candles(
        instrument: @instrument,
        timeframe: '1D',
        candles_data: candles_data
      )

      assert result[:success]
      assert_equal 1, result[:skipped]
      assert_equal 1, CandleSeriesRecord.count # Still only 1
    end

    test 'should update candle if data changed' do
      # Create existing candle
      create(:daily_candle, instrument: @instrument, timestamp: 1.day.ago, close: 100.0)

      candles_data = [
        {
          timestamp: 1.day.ago,
          open: 100.0,
          high: 105.0,
          low: 99.0,
          close: 105.0, # Changed
          volume: 1_000_000
        }
      ]

      result = Ingestor.upsert_candles(
        instrument: @instrument,
        timeframe: '1D',
        candles_data: candles_data
      )

      assert result[:success]
      assert_equal 1, result[:upserted]
      assert_equal 105.0, CandleSeriesRecord.first.close.to_f
    end
  end
end

