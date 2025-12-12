# frozen_string_literal: true

module Candles
  class WeeklyIngestor < ApplicationService
    DEFAULT_WEEKS_BACK = 52

    def self.call(instruments: nil, weeks_back: nil)
      new(instruments: instruments, weeks_back: weeks_back).call
    end

    def initialize(instruments: nil, weeks_back: nil)
      # Filter by segment (equity/index) instead of instrument_type
      # instrument_type values from CSV are like "ES", "Other" which don't match "EQUITY"/"INDEX"
      @instruments = instruments || Instrument.where(segment: %w[equity index])
      @weeks_back = weeks_back || DEFAULT_WEEKS_BACK
    end

    def call
      results = {
        processed: 0,
        success: 0,
        failed: 0,
        total_candles: 0,
        errors: [],
      }

      @instruments.find_each(batch_size: 100) do |instrument|
        result = fetch_and_store_weekly_candles(instrument)
        results[:processed] += 1

        if result[:success]
          results[:success] += 1
          results[:total_candles] += result[:upserted] || 0
        else
          results[:failed] += 1
          results[:errors] << { instrument: instrument.symbol_name, error: result[:error] }
        end

        # Rate limiting: delay to avoid API throttling (same as DailyIngestor)
        delay_seconds = (AlgoConfig.fetch[:dhanhq] || {})[:candle_ingestion_delay_seconds] || 0.5
        delay_interval = (AlgoConfig.fetch[:dhanhq] || {})[:candle_ingestion_delay_interval] || 5
        sleep(delay_seconds) if (results[:processed] % delay_interval).zero? && results[:processed] < @total_count
      end

      log_summary(results)
      results
    end

    private

    def fetch_and_store_weekly_candles(instrument)
      return { success: false, error: "Invalid instrument" } if instrument.blank?
      return { success: false, error: "Missing security_id" } if instrument.security_id.blank?

      # Calculate date range (weeks back)
      to_date = Time.zone.today - 1 # Yesterday
      from_date = to_date - (@weeks_back * 7).days

      # Fetch daily candles and aggregate to weekly
      daily_candles = fetch_daily_candles(
        instrument: instrument,
        from_date: from_date,
        to_date: to_date,
      )

      return { success: false, error: "No daily candles data received" } if daily_candles.blank?

      # Aggregate daily candles to weekly
      weekly_candles = aggregate_to_weekly(daily_candles)

      return { success: false, error: "No weekly candles after aggregation" } if weekly_candles.empty?

      # Upsert weekly candles to database
      result = Ingestor.upsert_candles(
        instrument: instrument,
        timeframe: "1W",
        candles_data: weekly_candles,
      )

      if result[:success]
        Rails.logger.info(
          "[Candles::WeeklyIngestor] #{instrument.symbol_name}: " \
          "upserted=#{result[:upserted]}, skipped=#{result[:skipped]}, total=#{result[:total]}",
        )
      end

      result
    rescue StandardError => e
      error_msg = "Failed to fetch weekly candles for #{instrument&.symbol_name}: #{e.message}"
      Rails.logger.error("[Candles::WeeklyIngestor] #{error_msg}")
      { success: false, error: error_msg }
    end

    def fetch_daily_candles(instrument:, from_date:, to_date:)
      # Use Instrument's historical_ohlc method to fetch daily candles
      instrument.historical_ohlc(from_date: from_date, to_date: to_date, oi: false)
    rescue StandardError => e
      Rails.logger.error(
        "[Candles::WeeklyIngestor] DhanHQ API error for #{instrument.symbol_name}: #{e.message}",
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
      size = data["high"]&.size || 0
      return [] if size.zero?

      (0...size).map do |i|
        {
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

    def log_summary(results)
      Rails.logger.info(
        "[Candles::WeeklyIngestor] Summary: " \
        "processed=#{results[:processed]}, " \
        "success=#{results[:success]}, " \
        "failed=#{results[:failed]}, " \
        "total_candles=#{results[:total_candles]}",
      )

      return unless results[:errors].any?

      Rails.logger.warn(
        "[Candles::WeeklyIngestor] Errors (#{results[:errors].size}): " \
        "#{results[:errors].first(5).pluck(:instrument).join(', ')}",
      )
    end
  end
end
