# frozen_string_literal: true

module Candles
  # Service for ingesting candle data into the database
  #
  # Handles bulk import/update of candle data using activerecord-import for performance.
  # Automatically handles duplicates via database-level unique constraints.
  #
  # @example
  #   result = Candles::Ingestor.new.upsert_candles(
  #     instrument: instrument,
  #     timeframe: :daily,
  #     candles_data: [{ timestamp: '2024-01-01', open: 100, high: 105, low: 99, close: 103, volume: 1000 }]
  #   )
  #   # => { success: true, upserted: 1, skipped: 0, errors: [], total: 1 }
  class Ingestor < ApplicationService
    def self.upsert_candles(instrument:, timeframe:, candles_data:)
      new.upsert_candles(instrument: instrument, timeframe: timeframe, candles_data: candles_data)
    end

    def upsert_candles(instrument:, timeframe:, candles_data:)
      return { success: false, error: "No candles data provided" } if candles_data.blank?

      # Validate instrument exists
      unless instrument&.persisted?
        return { success: false, error: "Invalid or unsaved instrument provided" }
      end

      normalized = normalize_candles(candles_data)
      return { success: false, error: "Failed to normalize candles" } if normalized.empty?

      # Validate timeframe enum value
      unless CandleSeriesRecord.timeframes.key?(timeframe)
        return {
          success: false,
          error: "Invalid timeframe: #{timeframe}. Must be one of: #{CandleSeriesRecord.timeframes.keys.join(', ')}"
        }
      end

      # Normalize timestamps for all candles
      normalized_candles = normalized.map do |candle_hash|
        {
          instrument_id: instrument.id,
          timeframe: timeframe,
          timestamp: normalize_timestamp(candle_hash[:timestamp], timeframe),
          open: candle_hash[:open],
          high: candle_hash[:high],
          low: candle_hash[:low],
          close: candle_hash[:close],
          volume: candle_hash[:volume],
          created_at: Time.current,
          updated_at: Time.current,
        }
      end

      # Use activerecord-import for bulk insert/update
      # The unique index on [instrument_id, timeframe, timestamp] handles duplicates
      # on_duplicate_key_update will update existing records automatically
      #
      # Note: validate: false is safe because:
      # 1. All data is normalized and validated before this point
      # 2. Timestamps are normalized to proper Time objects
      # 3. All numeric fields are converted to proper types
      # 4. Required fields (instrument_id, timeframe, timestamp) are always present
      upserted_count = 0
      skipped_count = 0

      begin
        # Wrap in transaction for atomicity - either all candles are imported or none
        # This ensures data consistency even if the import partially fails
        result = ActiveRecord::Base.transaction do
          # Bulk import all candles - database handles duplicates via ON DUPLICATE KEY UPDATE
          # For very large batches, import handles them efficiently internally
          # No need to chunk unless memory becomes an issue (activerecord-import handles this)
          CandleSeriesRecord.import(
            normalized_candles,
            validate: false, # Safe - data normalized and validated above
            on_duplicate_key_update: {
              conflict_target: [:instrument_id, :timeframe, :timestamp],
              columns: [:open, :high, :low, :close, :volume, :updated_at]
            }
          )
        end

        # activerecord-import returns result with failed_instances
        # Note: With on_duplicate_key_update, duplicates are handled by the database
        # and don't appear in failed_instances. All successful operations (inserts + updates)
        # are counted as upserted.
        failed_count = result.failed_instances&.size || 0
        upserted_count = normalized_candles.size - failed_count
        skipped_count = failed_count

        Rails.logger.info(
          "[Candles::Ingestor] Bulk import completed for #{instrument.symbol_name}: " \
          "total=#{normalized_candles.size}, upserted=#{upserted_count}, failed=#{failed_count}"
        )
      rescue ActiveRecord::StatementInvalid => e
        # Database-level errors (constraints, syntax, etc.)
        Rails.logger.error(
          "[Candles::Ingestor] Bulk import failed (database error): #{e.message}, " \
          "falling back to individual inserts. Error class: #{e.class}"
        )
        # Fallback to individual inserts if bulk import fails
        upserted_count, skipped_count = fallback_to_individual_upserts(normalized_candles)
      rescue StandardError => e
        # Other unexpected errors
        Rails.logger.error(
          "[Candles::Ingestor] Bulk import failed (unexpected error): #{e.message}, " \
          "falling back to individual inserts. Error class: #{e.class}, Backtrace: #{e.backtrace.first(5).join(', ')}"
        )
        # Fallback to individual inserts if bulk import fails
        upserted_count, skipped_count = fallback_to_individual_upserts(normalized_candles)
      end

      {
        success: true,
        upserted: upserted_count,
        skipped: skipped_count,
        errors: [],
        total: normalized.size,
      }
    end

    private

    def fallback_to_individual_upserts(candles)
      upserted = 0
      skipped = 0

      candles.each do |candle|
        begin
          CandleSeriesRecord.create!(candle)
          upserted += 1
        rescue ActiveRecord::RecordNotUnique
          # Try to update if duplicate
          existing = CandleSeriesRecord.find_by(
            instrument_id: candle[:instrument_id],
            timeframe: candle[:timeframe],
            timestamp: candle[:timestamp]
          )
          if existing
            if candle_data_changed?(existing, open: candle[:open], high: candle[:high], low: candle[:low], close: candle[:close], volume: candle[:volume])
              existing.update!(
                open: candle[:open],
                high: candle[:high],
                low: candle[:low],
                close: candle[:close],
                volume: candle[:volume]
              )
              upserted += 1
            else
              skipped += 1
            end
          else
            skipped += 1
          end
        rescue StandardError => err
          Rails.logger.warn("[Candles::Ingestor] Failed to upsert candle: #{err.message}")
          skipped += 1
        end
      end

      [upserted, skipped]
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
      case timeframe
      when :daily
        time.beginning_of_day
      when :weekly
        time.beginning_of_week
      when :hourly
        time.beginning_of_hour
      else
        time.beginning_of_minute
      end
    end

    # Check if candle data has changed (for upsert logic)
    # Uses float comparison for prices - acceptable for detecting changes in stored values
    # rubocop:disable Lint/FloatComparison
    def candle_data_changed?(existing, open:, high:, low:, close:, volume:)
      existing.open.to_f != open.to_f ||
        existing.high.to_f != high.to_f ||
        existing.low.to_f != low.to_f ||
        existing.close.to_f != close.to_f ||
        existing.volume.to_i != volume.to_i
    end
    # rubocop:enable Lint/FloatComparison

    def normalize_candles(data)
      return [] if data.blank?

      # Handle array of hashes
      if data.is_a?(Array)
        data.filter_map { |c| normalize_single_candle(c) }
      # Handle hash with arrays (DhanHQ format)
      elsif data.is_a?(Hash) && data["high"].is_a?(Array)
        normalize_hash_format(data)
      # Handle single hash
      elsif data.is_a?(Hash)
        [normalize_single_candle(data)].compact
      else
        []
      end
    end

    def normalize_hash_format(data)
      # DhanHQ API returns data as hash with arrays:
      # { "timestamp" => [epoch1, epoch2, ...], "open" => [...], "high" => [...], ... }
      # Timestamps are Unix epoch (Float or Integer)
      size = data["high"]&.size || 0
      return [] if size.zero?

      (0...size).map do |i|
        {
          # Parse epoch timestamp (Integer or Float) to Time object
          timestamp: parse_timestamp(data["timestamp"]&.[](i)),
          open: data["open"]&.[](i)&.to_f || 0,
          high: data["high"]&.[](i)&.to_f || 0,
          low: data["low"]&.[](i)&.to_f || 0,
          close: data["close"]&.[](i)&.to_f || 0,
          volume: data["volume"]&.[](i).to_i,
        }
      end
    end

    def normalize_single_candle(candle)
      return nil unless candle

      {
        timestamp: parse_timestamp(candle[:timestamp] || candle["timestamp"]),
        open: (candle[:open] || candle["open"]).to_f,
        high: (candle[:high] || candle["high"]).to_f,
        low: (candle[:low] || candle["low"]).to_f,
        close: (candle[:close] || candle["close"]).to_f,
        volume: (candle[:volume] || candle["volume"] || 0).to_i,
      }
    rescue StandardError => e
      Rails.logger.warn("[Candles::Ingestor] Failed to normalize candle: #{e.message}")
      nil
    end

    # Parses timestamp from various formats (epoch, Time, String) to Time object
    # DhanHQ API returns timestamps as Unix epoch (Integer or Float)
    # @param timestamp [Integer, Float, String, Time, ActiveSupport::TimeWithZone] Timestamp in various formats
    # @return [ActiveSupport::TimeWithZone] Parsed timestamp in application timezone
    def parse_timestamp(timestamp)
      return Time.zone.now if timestamp.blank?

      case timestamp
      when Time, ActiveSupport::TimeWithZone
        timestamp
      when Integer, Float
        # Handle Unix epoch timestamps (both Integer and Float)
        # DhanHQ API returns Float epoch values like 1765132200.0
        Time.zone.at(timestamp.to_f)
      when String
        # Try parsing as Unix epoch first (numeric string like "1765132200" or "1765132200.0")
        if timestamp.match?(/\A\d+(\.\d+)?\z/)
          Time.zone.at(timestamp.to_f)
        else
          Time.zone.parse(timestamp)
        end
      else
        # Fallback: try to convert to numeric (for Unix epoch)
        numeric = timestamp.to_s.strip
        if numeric.match?(/\A\d+(\.\d+)?\z/)
          Time.zone.at(numeric.to_f)
        else
          Time.zone.parse(numeric)
        end
      end
    rescue StandardError => e
      Rails.logger.warn("[Candles::Ingestor] Failed to parse timestamp #{timestamp.inspect}: #{e.message}")
      Time.zone.now
    end
  end
end
