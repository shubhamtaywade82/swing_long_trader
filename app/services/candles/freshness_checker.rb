# frozen_string_literal: true

module Candles
  # Service to check if candles are up-to-date and trigger ingestion if stale
  # Ensures candles are fresh before analysis/screening operations
  # Accounts for weekends and market holidays - uses trading days instead of calendar days
  class FreshnessChecker < ApplicationService
    # Maximum age for candles to be considered fresh (in trading days)
    # Default: 1 trading day (candles should be at least from last trading day)
    DEFAULT_MAX_TRADING_DAYS = 1

    # Minimum percentage of instruments that must have fresh candles
    # Default: 80% (allows for some instruments to be missing data)
    DEFAULT_MIN_FRESHNESS_PERCENTAGE = 80.0

    def self.ensure_fresh(timeframe: :daily, max_trading_days: nil, min_freshness_percentage: nil, auto_ingest: true)
      new(
        timeframe: timeframe,
        max_trading_days: max_trading_days,
        min_freshness_percentage: min_freshness_percentage,
        auto_ingest: auto_ingest,
      ).ensure_fresh
    end

    def initialize(timeframe: :daily, max_trading_days: nil, min_freshness_percentage: nil, auto_ingest: true)
      @timeframe = timeframe
      @max_trading_days = max_trading_days || DEFAULT_MAX_TRADING_DAYS
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

      # Calculate cutoff date based on trading days (accounts for weekends and holidays)
      cutoff_date = last_trading_day_ago(@max_trading_days)
      fresh_count = 0

      # Check freshness for each instrument
      instruments.find_each(batch_size: 100) do |instrument|
        latest_candle = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: @timeframe)
        next unless latest_candle

        latest_date = latest_candle.timestamp.to_date
        # Consider fresh if latest candle is from cutoff_date or later
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
        cutoff_trading_days_ago: @max_trading_days,
        timeframe: @timeframe,
      }
    end

    def self.check_freshness(timeframe: :daily, max_trading_days: nil, min_freshness_percentage: nil, auto_ingest: false)
      new(
        timeframe: timeframe,
        max_trading_days: max_trading_days,
        min_freshness_percentage: min_freshness_percentage,
        auto_ingest: auto_ingest,
      ).check_freshness
    end

    private

    # Calculate the date that is N trading days ago
    # Accounts for weekends and market holidays
    def last_trading_day_ago(trading_days_ago)
      return Time.zone.today if trading_days_ago.zero?

      # Start from yesterday (today's data may not be complete)
      date = Time.zone.today - 1.day
      trading_days_found = 0

      # Go back in time until we find enough trading days
      # Limit to 1 year ago to prevent infinite loops
      max_lookback = 1.year.ago.to_date

      while trading_days_found < trading_days_ago && date >= max_lookback
        # Check if this is a trading day (weekday and not a holiday)
        if trading_day?(date)
          trading_days_found += 1
          # If we've found enough trading days, return this date
          return date if trading_days_found == trading_days_ago
        end

        date -= 1.day
      end

      # If we couldn't find enough trading days (e.g., near holidays),
      # return the date we found (which might be older than requested)
      date + 1.day # Add back the last decrement
    end

    # Check if a date is a trading day (weekday and not a holiday)
    def trading_day?(date)
      # Must be a weekday (Monday = 1, Friday = 5)
      return false unless (1..5).include?(date.wday)

      # Must not be a market holiday
      return false if MarketHoliday.holiday?(date)

      true
    end

    def trigger_ingestion
      case @timeframe
      when :daily, "1D"
        Rails.logger.info("[Candles::FreshnessChecker] Triggering daily candle ingestion...")
        result = DailyIngestor.call
        {
          success: result[:success].positive?,
          processed: result[:processed],
          total_candles: result[:total_candles],
        }
      when :weekly, "1W"
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
