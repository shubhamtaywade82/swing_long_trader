# frozen_string_literal: true

module Candles
  # Helper service to load candles from database and convert to CandleSeries format
  # This bridges the gap between CandleSeriesRecord (ActiveRecord) and CandleSeries (plain Ruby class)
  class Loader
    def self.load_for_instrument(instrument:, timeframe:, limit: nil, from_date: nil, to_date: nil)
      new.load_for_instrument(
        instrument: instrument,
        timeframe: timeframe,
        limit: limit,
        from_date: from_date,
        to_date: to_date,
      )
    end

    def load_for_instrument(instrument:, timeframe:, limit: nil, from_date: nil, to_date: nil)
      # Load candles from database
      scope = CandleSeriesRecord
              .for_instrument(instrument)
              .for_timeframe(timeframe)
              .ordered

      scope = scope.between_dates(from_date, to_date) if from_date && to_date
      scope = scope.limit(limit) if limit

      records = scope.to_a
      return nil if records.empty?

      # Convert to CandleSeries format
      convert_to_candle_series(
        instrument: instrument,
        timeframe: timeframe,
        records: records,
      )
    end

    def load_latest(instrument:, timeframe:, count: 100)
      records = CandleSeriesRecord
                .for_instrument(instrument)
                .for_timeframe(timeframe)
                .recent(count)
                .reverse # Reverse to get chronological order

      return nil if records.empty?

      convert_to_candle_series(
        instrument: instrument,
        timeframe: timeframe,
        records: records,
      )
    end

    private

    def convert_to_candle_series(instrument:, timeframe:, records:)
      # Create CandleSeries instance
      series = CandleSeries.new(
        symbol: instrument.symbol_name,
        interval: timeframe,
      )

      # Convert each record to Candle object and add to series
      records.each do |record|
        candle = Candle.new(
          timestamp: record.timestamp,
          open: record.open,
          high: record.high,
          low: record.low,
          close: record.close,
          volume: record.volume,
        )
        series.add_candle(candle)
      end

      # Ensure candles are sorted by timestamp (safety check)
      series.candles.sort_by!(&:timestamp)

      series
    end
  end
end
