# frozen_string_literal: true

module Backtesting
  # Loads historical candles for backtesting
  class DataLoader
    def self.load_for_instruments(instruments:, timeframe:, from_date:, to_date:, interpolate_missing: false)
      new.load_for_instruments(
        instruments: instruments,
        timeframe: timeframe,
        from_date: from_date,
        to_date: to_date,
        interpolate_missing: interpolate_missing,
      )
    end

    def load_for_instruments(instruments:, timeframe:, from_date:, to_date:, _interpolate_missing: false)
      data = {}

      instruments.find_each do |instrument|
        series = load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
          from_date: from_date,
          to_date: to_date,
        )

        data[instrument.id] = series if series
      end

      data
    end

    def load_for_instrument(instrument:, timeframe:, from_date:, to_date:, interpolate_missing: false)
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
        interval: timeframe,
      )

      # Build hash of existing candles by date
      existing_candles = {}
      records.each do |record|
        date = record.timestamp.to_date
        existing_candles[date] = Candle.new(
          timestamp: record.timestamp,
          open: record.open,
          high: record.high,
          low: record.low,
          close: record.close,
          volume: record.volume,
        )
      end

      # Fill missing dates if interpolation is enabled
      if interpolate_missing && timeframe == "1D"
        fill_missing_daily_candles(series, existing_candles, from_date, to_date, interpolate_missing)
      else
        # Just add existing candles in order
        records.each do |record|
          series.add_candle(existing_candles[record.timestamp.to_date])
        end
      end

      series
    end

    def fill_missing_daily_candles(series, existing_candles, from_date, to_date, interpolate_missing)
      current_date = from_date.to_date
      last_candle = nil

      while current_date <= to_date.to_date
        if existing_candles[current_date]
          # Use existing candle
          candle = existing_candles[current_date]
          series.add_candle(candle)
          last_candle = candle
        elsif interpolate_missing && last_candle
          # Interpolate missing candle (forward fill)
          interpolated = Candle.new(
            timestamp: current_date.beginning_of_day,
            open: last_candle.close,
            high: last_candle.close,
            low: last_candle.close,
            close: last_candle.close,
            volume: 0, # No volume for interpolated candles
          )
          series.add_candle(interpolated)
          # Don't update last_candle - keep using previous real candle for interpolation
        end
        # If no last_candle and no existing candle, skip (can't interpolate without prior data)

        current_date += 1.day
      end
    end

    def validate_data(data, min_candles: 50, max_gap_days: 5)
      validated = {}

      data.each do |instrument_id, series|
        next unless series&.candles&.any?

        # Check for large gaps in data
        gaps = detect_gaps(series.candles)
        large_gaps = gaps.select { |gap| gap[:days] > max_gap_days }

        if large_gaps.any?
          Rails.logger.warn(
            "[Backtesting::DataLoader] Large gaps detected for instrument #{instrument_id}: " \
            "#{large_gaps.map { |g| "#{g[:days]} days" }.join(', ')}",
          )
        end

        # Validate minimum candles
        if series.candles.size >= min_candles
          validated[instrument_id] = series
        else
          Rails.logger.warn(
            "[Backtesting::DataLoader] Insufficient candles for instrument #{instrument_id}: " \
            "#{series.candles.size} < #{min_candles}",
          )
        end
      end

      validated
    end

    def detect_gaps(candles)
      return [] if candles.size < 2

      gaps = []
      (1...candles.size).each do |i|
        prev_date = candles[i - 1].timestamp.to_date
        curr_date = candles[i].timestamp.to_date
        gap_days = (curr_date - prev_date).to_i - 1

        next unless gap_days.positive?

        gaps << {
          from: prev_date,
          to: curr_date,
          days: gap_days,
        }
      end

      gaps
    end
  end
end
