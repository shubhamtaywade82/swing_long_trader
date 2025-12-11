# frozen_string_literal: true

module Backtesting
  # Loads historical candles for backtesting
  class DataLoader
    def self.load_for_instruments(instruments:, timeframe:, from_date:, to_date:)
      new.load_for_instruments(
        instruments: instruments,
        timeframe: timeframe,
        from_date: from_date,
        to_date: to_date
      )
    end

    def load_for_instruments(instruments:, timeframe:, from_date:, to_date:)
      data = {}

      instruments.find_each do |instrument|
        series = load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
          from_date: from_date,
          to_date: to_date
        )

        data[instrument.id] = series if series
      end

      data
    end

    def load_for_instrument(instrument:, timeframe:, from_date:, to_date:)
      # Load candles from database
      records = CandleSeriesRecord
        .for_instrument(instrument)
        .for_timeframe(timeframe)
        .between_dates(from_date, to_date)
        .ordered
        .to_a

      return nil if records.empty?

      # Convert to CandleSeries format
      series = CandleSeries.new(
        symbol: instrument.symbol_name,
        interval: timeframe
      )

      records.each do |record|
        candle = Candle.new(
          timestamp: record.timestamp,
          open: record.open,
          high: record.high,
          low: record.low,
          close: record.close,
          volume: record.volume
        )
        series.add_candle(candle)
      end

      series
    end

    def validate_data(data, min_candles: 50)
      validated = {}

      data.each do |instrument_id, series|
        if series&.candles&.size.to_i >= min_candles
          validated[instrument_id] = series
        else
          Rails.logger.warn(
            "[Backtesting::DataLoader] Insufficient candles for instrument #{instrument_id}: " \
            "#{series&.candles&.size || 0} < #{min_candles}"
          )
        end
      end

      validated
    end
  end
end


