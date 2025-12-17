# frozen_string_literal: true

module Candles
  # Service to check if candles are up-to-date and trigger ingestion if stale
  # Ensures candles are fresh before analysis/screening operations
  class FreshnessChecker < ApplicationService
    # Maximum age for candles to be considered fresh (in days)
    # Default: 1 day (candles should be at least from yesterday)
    DEFAULT_MAX_AGE_DAYS = 1

    # Minimum percentage of instruments that must have fresh candles
    # Default: 80% (allows for some instruments to be missing data)
    DEFAULT_MIN_FRESHNESS_PERCENTAGE = 80.0

    def self.ensure_fresh(timeframe: "1D", max_age_days: nil, min_freshness_percentage: nil, auto_ingest: true)
      new(
        timeframe: timeframe,
        max_age_days: max_age_days,
        min_freshness_percentage: min_freshness_percentage,
        auto_ingest: auto_ingest,
      ).ensure_fresh
    end

    def initialize(timeframe: "1D", max_age_days: nil, min_freshness_percentage: nil, auto_ingest: true)
      @timeframe = timeframe
      @max_age_days = max_age_days || DEFAULT_MAX_AGE_DAYS
      @min_freshness_percentage = min_freshness_percentage || DEFAULT_MIN_FRESHNESS_PERCENTAGE
      @auto_ingest = auto_ingest
    end

    def ensure_fresh
      return { fresh: true, message: "Skipped in test environment" } if Rails.env.test? && !@auto_ingest

      check_result = check_freshness

      if check_result[:fresh]
        Rails.logger.info(
          "[Candles::FreshnessChecker] Candles are fresh: " \
          "#{check_result[:fresh_count]}/#{check_result[:total_count]} instruments " \
          "(#{check_result[:freshness_percentage].round(1)}%)",
        )
        return check_result
      end

      if @auto_ingest
        Rails.logger.warn(
          "[Candles::FreshnessChecker] Candles are stale (#{check_result[:freshness_percentage].round(1)}% fresh). " \
          "Triggering ingestion for #{@timeframe} timeframe...",
        )
        ingest_result = trigger_ingestion
        check_result.merge(ingested: true, ingestion_result: ingest_result)
      else
        Rails.logger.warn(
          "[Candles::FreshnessChecker] Candles are stale but auto_ingest is disabled. " \
          "Manual ingestion required.",
        )
        check_result.merge(ingested: false, requires_manual_ingestion: true)
      end
    rescue StandardError => e
      Rails.logger.error("[Candles::FreshnessChecker] Error checking freshness: #{e.message}")
      { fresh: false, error: e.message }
    end

    def check_freshness
      instruments = Instrument.where(segment: %w[equity index])
      total_count = instruments.count
      return { fresh: true, total_count: 0, fresh_count: 0, freshness_percentage: 100.0 } if total_count.zero?

      cutoff_date = Time.zone.today - @max_age_days.days
      fresh_count = 0

      # Check freshness for each instrument
      instruments.find_each(batch_size: 100) do |instrument|
        latest_candle = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: @timeframe)
        next unless latest_candle

        latest_date = latest_candle.timestamp.to_date
        fresh_count += 1 if latest_date >= cutoff_date
      end

      freshness_percentage = (fresh_count.to_f / total_count * 100).round(2)
      fresh = freshness_percentage >= @min_freshness_percentage

      {
        fresh: fresh,
        total_count: total_count,
        fresh_count: fresh_count,
        stale_count: total_count - fresh_count,
        freshness_percentage: freshness_percentage,
        cutoff_date: cutoff_date,
        timeframe: @timeframe,
      }
    end

    def self.check_freshness(timeframe: "1D", max_age_days: nil, min_freshness_percentage: nil, auto_ingest: false)
      new(
        timeframe: timeframe,
        max_age_days: max_age_days,
        min_freshness_percentage: min_freshness_percentage,
        auto_ingest: auto_ingest,
      ).check_freshness
    end

    private

    def trigger_ingestion
      case @timeframe
      when "1D"
        Rails.logger.info("[Candles::FreshnessChecker] Triggering daily candle ingestion...")
        result = DailyIngestor.call
        {
          success: result[:success].positive?,
          processed: result[:processed],
          total_candles: result[:total_candles],
        }
      when "1W"
        Rails.logger.info("[Candles::FreshnessChecker] Triggering weekly candle ingestion...")
        result = WeeklyIngestor.call
        {
          success: result[:success].positive?,
          processed: result[:processed],
          total_candles: result[:total_candles],
        }
      else
        Rails.logger.warn("[Candles::FreshnessChecker] Unknown timeframe: #{@timeframe}, skipping ingestion")
        { success: false, error: "Unknown timeframe: #{@timeframe}" }
      end
    end
  end
end
