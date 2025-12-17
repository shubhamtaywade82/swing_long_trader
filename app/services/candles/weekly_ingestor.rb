# frozen_string_literal: true

module Candles
  class WeeklyIngestor < ApplicationService
    DEFAULT_WEEKS_BACK = 52

    def self.call(instruments: nil, weeks_back: nil)
      new(instruments: instruments, weeks_back: weeks_back).call
    end

    def initialize(instruments: nil, weeks_back: nil)
      # ApplicationService doesn't define initialize, so super is not needed
      # Filter by segment (equity/index) instead of instrument_type
      # instrument_type values from CSV are like "ES", "Other" which don't match "EQUITY"/"INDEX"
      @instruments = instruments || Instrument.where(segment: %w[equity index])
      @weeks_back = weeks_back || DEFAULT_WEEKS_BACK
      @total_count = @instruments.count
    end

    def call
      results = {
        processed: 0,
        success: 0,
        failed: 0,
        skipped_up_to_date: 0,
        total_candles: 0,
        errors: [],
      }

      start_time = Time.current
      puts "\n📊 Starting weekly candle ingestion for #{@total_count} instruments..."
      puts "   Aggregating from daily candles (no API calls needed)\n"

      @instruments.find_each(batch_size: 100) do |instrument|
        result = fetch_and_store_weekly_candles(instrument)
        results[:processed] += 1

        if result[:success]
          results[:success] += 1
          results[:total_candles] += result[:upserted] || 0
          results[:skipped_up_to_date] += 1 if result[:action] == :skipped_up_to_date
        else
          results[:failed] += 1
          results[:errors] << { instrument: instrument.symbol_name, error: result[:error] }
        end

        # Progress logging every 10 instruments
        if (results[:processed] % 10).zero?
          elapsed = Time.current - start_time
          rate = results[:processed].to_f / elapsed
          remaining = begin
            (@total_count - results[:processed]) / rate
          rescue StandardError
            0
          end
          puts "   Progress: #{results[:processed]}/#{@total_count} (#{(results[:processed].to_f / @total_count * 100).round(1)}%) | " \
               "Success: #{results[:success]} | Failed: #{results[:failed]} | " \
               "Up-to-date: #{results[:skipped_up_to_date]} | " \
               "ETA: #{(remaining / 60).round(1)} min"
        end
      end

      log_summary(results, Time.current - start_time)
      results
    end

    private

    def fetch_and_store_weekly_candles(instrument)
      return { success: false, error: "Invalid instrument" } if instrument.blank?
      return { success: false, error: "Missing security_id" } if instrument.security_id.blank?

      # Calculate date range
      to_date = Time.zone.today - 1 # Yesterday

      # Check for existing weekly candles to optimize date range
      latest_weekly_candle = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: "1W")

      if latest_weekly_candle
        # Start from the week after the latest weekly candle
        latest_week_start = latest_weekly_candle.timestamp.beginning_of_week
        # Get the start of the next week (Monday after latest week)
        next_week_start = latest_week_start + 1.week
        # Convert to date for daily candle fetching
        from_date = next_week_start.to_date

        # If we already have data up to the current week, check if we need to update
        current_week_start = to_date.beginning_of_week
        latest_week_date = latest_week_start.to_date

        # If latest weekly candle is from current week or later, skip
        if latest_week_date >= current_week_start
          Rails.logger.debug do
            "[Candles::WeeklyIngestor] #{instrument.symbol_name}: " \
              "Already up-to-date (latest week: #{latest_week_date}, current week: #{current_week_start})"
          end
          return {
            success: true,
            upserted: 0,
            skipped: 0,
            total: 0,
            action: :skipped_up_to_date,
          }
        end

        # Ensure we don't fetch less than minimum required weeks (for initial gaps)
        # If latest weekly candle is very old (older than min_from_date), fetch from min_from_date to fill gaps
        # Otherwise, fetch from the week after latest weekly candle (incremental update)
        min_from_date = to_date - (@weeks_back * 7).days
        from_date = [from_date, min_from_date].max
      else
        # No existing weekly candles - fetch full range
        from_date = to_date - (@weeks_back * 7).days
      end

      # Fetch daily candles and aggregate to weekly (only for the optimized date range)
      daily_candles = fetch_daily_candles(
        instrument: instrument,
        from_date: from_date,
        to_date: to_date,
      )

      return { success: false, error: "No daily candles data received" } if daily_candles.blank?

      # Aggregate daily candles to weekly
      weekly_candles = aggregate_to_weekly(daily_candles)

      return { success: false, error: "No weekly candles after aggregation" } if weekly_candles.empty?

      # Upsert weekly candles to database (will skip existing ones)
      result = Ingestor.upsert_candles(
        instrument: instrument,
        timeframe: "1W",
        candles_data: weekly_candles,
      )

      if result[:success]
        action_type = latest_weekly_candle ? "updated" : "initial_load"
        Rails.logger.info(
          "[Candles::WeeklyIngestor] #{instrument.symbol_name} (#{action_type}): " \
          "upserted=#{result[:upserted]}, skipped=#{result[:skipped]}, total=#{result[:total]}, " \
          "date_range=#{from_date}..#{to_date}",
        )
      end

      result
    rescue StandardError => e
      error_msg = "Failed to fetch weekly candles for #{instrument&.symbol_name}: #{e.message}"
      Rails.logger.error("[Candles::WeeklyIngestor] #{error_msg}")
      { success: false, error: error_msg }
    end

    def fetch_daily_candles(instrument:, from_date:, to_date:)
      # Load daily candles from database (already ingested by DailyIngestor)
      # Use date range to load only relevant candles efficiently
      daily_series = instrument.load_daily_candles(
        limit: nil, # Load all candles in date range
        from_date: from_date,
        to_date: to_date,
      )
      return nil if daily_series.blank? || daily_series.candles.blank?

      # Additional filtering to ensure we only get candles in the date range
      # (load_daily_candles should handle this, but double-check for safety)
      filtered_candles = daily_series.candles.select do |candle|
        candle_time = candle.timestamp
        candle_time >= from_date.beginning_of_day && candle_time <= to_date.end_of_day
      end

      return nil if filtered_candles.empty?

      # Convert to hash format for aggregation
      filtered_candles.map do |candle|
        {
          timestamp: candle.timestamp,
          open: candle.open,
          high: candle.high,
          low: candle.low,
          close: candle.close,
          volume: candle.volume,
        }
      end
    rescue StandardError => e
      Rails.logger.error(
        "[Candles::WeeklyIngestor] Error loading daily candles for #{instrument.symbol_name}: #{e.message}",
      )
      nil
    end

    def aggregate_to_weekly(daily_candles)
      # Normalize candles data
      normalized = normalize_candles(daily_candles)
      return [] if normalized.empty?

      # Group by week (Monday to Sunday)
      weekly_groups = normalized.group_by do |candle|
        week_start = parse_timestamp(candle[:timestamp] || candle["timestamp"]).beginning_of_week
        week_start
      end

      # Aggregate each week
      weekly_groups.map do |week_start, week_candles|
        {
          timestamp: week_start,
          open: week_candles.first[:open] || week_candles.first["open"],
          high: week_candles.map { |c| c[:high] || c["high"] }.max,
          low: week_candles.map { |c| c[:low] || c["low"] }.min,
          close: week_candles.last[:close] || week_candles.last["close"],
          volume: week_candles.sum { |c| c[:volume] || c["volume"] || 0 },
        }
      end.sort_by { |c| c[:timestamp] }
    end

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
      # Handles DhanHQ API format: hash with arrays
      # { "timestamp" => [epoch1, epoch2, ...], "open" => [...], "high" => [...], ... }
      # Timestamps are Unix epoch (Float or Integer)
      # Note: Weekly ingestor typically loads from DB (Time objects), but this handles edge cases
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
      Rails.logger.warn("[Candles::WeeklyIngestor] Failed to normalize candle: #{e.message}")
      nil
    end

    # Parses timestamp from various formats (epoch, Time, String) to Time object
    # Handles epoch timestamps (Integer or Float) from API responses
    # Daily candles from DB are already Time objects, but this handles edge cases
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
          parsed = Time.zone.parse(timestamp)
          parsed || Time.zone.now # Fallback if parse returns nil
        end
      else
        # Fallback: try to convert to numeric (for Unix epoch)
        numeric = timestamp.to_s.strip
        if numeric.match?(/\A\d+(\.\d+)?\z/)
          Time.zone.at(numeric.to_f)
        else
          parsed = Time.zone.parse(timestamp.to_s)
          parsed || Time.zone.now # Fallback if parse returns nil
        end
      end
    rescue StandardError => e
      Rails.logger.warn("[Candles::WeeklyIngestor] Failed to parse timestamp #{timestamp.inspect}: #{e.message}")
      Time.zone.now
    end

    def log_summary(results, duration)
      puts "\n✅ Weekly candle ingestion completed!"
      puts "   Duration: #{(duration / 60).round(1)} minutes"
      puts "   Processed: #{results[:processed]}"
      puts "   Success: #{results[:success]}"
      puts "   Failed: #{results[:failed]}"
      puts "   Already up-to-date: #{results[:skipped_up_to_date]}" if results[:skipped_up_to_date].positive?
      puts "   Total candles: #{results[:total_candles]}"

      Rails.logger.info(
        "[Candles::WeeklyIngestor] Summary: " \
        "processed=#{results[:processed]}, " \
        "success=#{results[:success]}, " \
        "failed=#{results[:failed]}, " \
        "skipped_up_to_date=#{results[:skipped_up_to_date]}, " \
        "total_candles=#{results[:total_candles]}, " \
        "duration=#{duration.round(2)}s",
      )

      return unless results[:errors].any?

      puts "\n⚠️  Errors encountered (#{results[:errors].size}):"
      results[:errors].first(10).each do |error|
        puts "   - #{error[:instrument]}: #{error[:error][0..100]}"
      end

      Rails.logger.warn(
        "[Candles::WeeklyIngestor] Errors (#{results[:errors].size}): " \
        "#{results[:errors].first(5).pluck(:instrument).join(', ')}",
      )
    end
  end
end
