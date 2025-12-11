# frozen_string_literal: true

require 'test_helper'

module Backtesting
  class DataLoaderTest < ActiveSupport::TestCase
    setup do
      @instrument = create(:instrument)
      # Create candles for date range
      @from_date = 10.days.ago.to_date
      @to_date = Date.today

      10.times do |i|
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
    end

    test 'should load candles for instrument' do
      loader = DataLoader.new
      series = loader.load_for_instrument(
        instrument: @instrument,
        timeframe: '1D',
        from_date: @from_date,
        to_date: @to_date
      )

      assert_not_nil series
      assert series.candles.any?
      assert_equal '1D', series.interval
    end

    test 'should validate data with minimum candles' do
      loader = DataLoader.new
      data = {
        @instrument.id => create_series_with_candles(60),
        create(:instrument).id => create_series_with_candles(30) # Insufficient
      }

      validated = loader.validate_data(data, min_candles: 50)

      assert_equal 1, validated.size
      assert validated.key?(@instrument.id)
    end

    test 'should load for multiple instruments' do
      instrument2 = create(:instrument)
      create_list(:daily_candle, 10, instrument: instrument2)

      data = DataLoader.load_for_instruments(
        instruments: Instrument.where(id: [@instrument.id, instrument2.id]),
        timeframe: '1D',
        from_date: @from_date,
        to_date: @to_date
      )

      assert_equal 2, data.size
      assert data.key?(@instrument.id)
      assert data.key?(instrument2.id)
    end

    private

    def create_series_with_candles(count)
      series = CandleSeries.new(symbol: 'TEST', interval: '1D')
      count.times do |i|
        series.add_candle(
          Candle.new(
            timestamp: i.days.ago,
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1_000_000
          )
        )
      end
      series
    end
  end
end

