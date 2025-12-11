# frozen_string_literal: true

module Candles
  # Base helper for candle ingestion with deduplication and upsert logic
  class Ingestor < ApplicationService

    def self.upsert_candles(instrument:, timeframe:, candles_data:)
      new.upsert_candles(instrument: instrument, timeframe: timeframe, candles_data: candles_data)
    end

    def upsert_candles(instrument:, timeframe:, candles_data:)
      return { success: false, error: 'No candles data provided' } if candles_data.blank?

      normalized = normalize_candles(candles_data)
      return { success: false, error: 'Failed to normalize candles' } if normalized.empty?

      upserted = 0
      skipped = 0
      errors = []

      normalized.each do |candle_hash|
        result = upsert_single_candle(
          instrument: instrument,
          timeframe: timeframe,
          timestamp: candle_hash[:timestamp],
          open: candle_hash[:open],
          high: candle_hash[:high],
          low: candle_hash[:low],
          close: candle_hash[:close],
          volume: candle_hash[:volume]
        )

        if result[:success]
          upserted += 1
        elsif result[:skipped]
          skipped += 1
        else
          errors << result[:error]
        end
      end

      {
        success: true,
        upserted: upserted,
        skipped: skipped,
        errors: errors.compact,
        total: normalized.size
      }
    end

    private

    def upsert_single_candle(instrument:, timeframe:, timestamp:, open:, high:, low:, close:, volume:)
      # Normalize timestamp to beginning of candle period
      normalized_timestamp = normalize_timestamp(timestamp, timeframe)

      # Check if candle already exists
      # For daily candles, normalize existing timestamps to beginning_of_day for comparison
      if timeframe == '1D'
        # Use range query to handle timestamp precision differences (microseconds, etc.)
        # The normalized timestamp should be at the beginning of the day
        day_start = normalized_timestamp.beginning_of_day
        day_end = normalized_timestamp.end_of_day
        # Use range syntax which is more reliable for timestamp comparisons
        existing = CandleSeriesRecord.where(
          instrument_id: instrument.id,
          timeframe: timeframe
        ).where(timestamp: day_start..day_end).first
      else
        existing = CandleSeriesRecord.find_by(
          instrument_id: instrument.id,
          timeframe: timeframe,
          timestamp: normalized_timestamp
        )
      end

      if existing
        # Update if data differs (in case of corrections)
        if candle_data_changed?(existing, open: open, high: high, low: low, close: close, volume: volume)
          existing.update!(
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume
          )
          return { success: true, action: :updated }
        end
        return { success: true, action: :skipped, skipped: true }
      end

      # Create new candle
      CandleSeriesRecord.create!(
        instrument_id: instrument.id,
        timeframe: timeframe,
        timestamp: normalized_timestamp,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume
      )

      { success: true, action: :created }
    rescue StandardError => e
      { success: false, error: e.message }
    end

    def normalize_timestamp(timestamp, timeframe)
      time = if timestamp.is_a?(Time)
               timestamp
             elsif timestamp.is_a?(Integer)
               Time.zone.at(timestamp)
             else
               Time.zone.parse(timestamp.to_s)
             end

      # Keep in application timezone (IST) for consistency with database
      return time.beginning_of_day if timeframe == '1D'
      return time.beginning_of_week if timeframe == '1W'

      # For intraday timeframes, round to nearest interval
      case timeframe
      when '15'
        time.beginning_of_minute + ((time.min / 15) * 15).minutes
      when '60'
        time.beginning_of_hour
      when '120'
        time.beginning_of_hour + ((time.hour / 2) * 2).hours
      else
        time.beginning_of_minute
      end
    end

    def candle_data_changed?(existing, open:, high:, low:, close:, volume:)
      existing.open.to_f != open.to_f ||
        existing.high.to_f != high.to_f ||
        existing.low.to_f != low.to_f ||
        existing.close.to_f != close.to_f ||
        existing.volume.to_i != volume.to_i
    end

    def normalize_candles(data)
      return [] if data.blank?

      # Handle array of hashes
      if data.is_a?(Array)
        data.map { |c| normalize_single_candle(c) }.compact
      # Handle hash with arrays (DhanHQ format)
      elsif data.is_a?(Hash) && data['high'].is_a?(Array)
        normalize_hash_format(data)
      # Handle single hash
      elsif data.is_a?(Hash)
        [normalize_single_candle(data)].compact
      else
        []
      end
    end

    def normalize_hash_format(data)
      size = data['high']&.size || 0
      return [] if size.zero?

      (0...size).map do |i|
        {
          timestamp: parse_timestamp(data['timestamp']&.[](i)),
          open: data['open']&.[](i)&.to_f || 0,
          high: data['high']&.[](i)&.to_f || 0,
          low: data['low']&.[](i)&.to_f || 0,
          close: data['close']&.[](i)&.to_f || 0,
          volume: data['volume']&.[](i)&.to_i || 0
        }
      end
    end

    def normalize_single_candle(candle)
      return nil unless candle

      {
        timestamp: parse_timestamp(candle[:timestamp] || candle['timestamp']),
        open: (candle[:open] || candle['open']).to_f,
        high: (candle[:high] || candle['high']).to_f,
        low: (candle[:low] || candle['low']).to_f,
        close: (candle[:close] || candle['close']).to_f,
        volume: (candle[:volume] || candle['volume'] || 0).to_i
      }
    rescue StandardError => e
      Rails.logger.warn("[Candles::Ingestor] Failed to normalize candle: #{e.message}")
      nil
    end

    def parse_timestamp(timestamp)
      return Time.zone.now if timestamp.blank?

      case timestamp
      when Time, ActiveSupport::TimeWithZone
        timestamp
      when Integer
        Time.zone.at(timestamp)
      when String
        Time.zone.parse(timestamp)
      else
        Time.zone.parse(timestamp.to_s)
      end
    rescue StandardError
      Time.zone.now
    end
  end
end

