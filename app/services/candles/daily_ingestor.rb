# frozen_string_literal: true

module Candles
  class DailyIngestor < ApplicationService
    DEFAULT_DAYS_BACK = 365
    # Rate limiting configuration
    DEFAULT_DELAY_SECONDS = 0.5 # Delay between requests (configurable)
    DEFAULT_DELAY_INTERVAL = 5 # Apply delay every N requests
    MAX_RETRIES = 3 # Maximum retries for rate limit errors
    INITIAL_RETRY_DELAY = 2 # Initial delay for exponential backoff (seconds)

    def self.call(instruments: nil, days_back: nil)
      new(instruments: instruments, days_back: days_back).call
    end

    def initialize(instruments: nil, days_back: nil)
      # ApplicationService doesn't define initialize, so super is not needed
      # Filter by segment (equity/index) instead of instrument_type
      # instrument_type values from CSV are like "ES", "Other" which don't match "EQUITY"/"INDEX"
      @instruments = instruments || Instrument.where(segment: %w[equity index])
      @days_back = days_back || DEFAULT_DAYS_BACK
      @total_count = @instruments.count
      @config = AlgoConfig.fetch[:dhanhq] || {}
      @delay_seconds = @config[:candle_ingestion_delay_seconds] || DEFAULT_DELAY_SECONDS
      @delay_interval = @config[:candle_ingestion_delay_interval] || DEFAULT_DELAY_INTERVAL
    end

    def call
      results = {
        processed: 0,
        success: 0,
        failed: 0,
        skipped_up_to_date: 0,
        skipped_time_window: 0,
        total_candles: 0,
        errors: [],
        rate_limit_retries: 0,
      }

      start_time = Time.current
      puts "\n📊 Starting daily candle ingestion for #{@total_count} instruments..."
      puts "   Rate limiting: #{@delay_seconds}s delay every #{@delay_interval} requests"
      puts "   Max retries: #{MAX_RETRIES} with exponential backoff\n"

      @instruments.find_each(batch_size: 100) do |instrument|
        result = fetch_and_store_daily_candles_with_retry(instrument)
        results[:processed] += 1

        if result[:success]
          results[:success] += 1
          results[:total_candles] += result[:upserted] || 0
          results[:skipped_up_to_date] += 1 if result[:action] == :skipped_up_to_date
        else
          results[:failed] += 1
          results[:errors] << { instrument: instrument.symbol_name, error: result[:error] }
        end

        results[:rate_limit_retries] += result[:retries] || 0

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
               "Skipped (time): #{results[:skipped_time_window]} | " \
               "ETA: #{(remaining / 60).round(1)} min"
        end

        # Rate limiting: delay to avoid API throttling
        sleep(@delay_seconds) if (results[:processed] % @delay_interval).zero? && results[:processed] < @total_count
      end

      log_summary(results, Time.current - start_time)
      results
    end

    private

    def fetch_and_store_daily_candles(instrument)
      return { success: false, error: "Invalid instrument" } if instrument.blank?
      return { success: false, error: "Missing security_id" } if instrument.security_id.blank?

      # Calculate date range and up-to-date threshold based on time
      # Before 3:30 PM: up-to-date = yesterday (skip if latest == yesterday)
      # After 3:30 PM: up-to-date = today (skip if latest == today)
      now_ist = Time.current.in_time_zone("Asia/Kolkata")
      market_close_today = now_ist.beginning_of_day.change(hour: 15, min: 30, sec: 0)

      to_date = Time.zone.today - 1 # Yesterday (fetch up to yesterday)
      up_to_date_threshold = if now_ist >= market_close_today
                               Time.zone.today # After 3:30 PM: check if we have today's data
                             else
                               Time.zone.today - 1 # Before 3:30 PM: check if we have yesterday's data
                             end

      # Check for existing candles to optimize date range
      latest_candle = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: :daily)

      if latest_candle
        # Start from the day after the latest candle (optimization: only fetch new data)
        latest_date = latest_candle.timestamp.to_date
        from_date = latest_date + 1.day

        # Skip only if latest timestamp equals the threshold date
        # After 3:30 PM: skip if latest == today
        # Before 3:30 PM: skip if latest == yesterday
        if latest_date == up_to_date_threshold
          Rails.logger.info do
            "[Candles::DailyIngestor] #{instrument.symbol_name}: " \
              "Already up-to-date (latest: #{latest_date}, threshold: #{up_to_date_threshold})"
          end
          return {
            success: true,
            upserted: 0,
            skipped: 0,
            total: 0,
            action: :skipped_up_to_date,
          }
        end

        # Calculate minimum required date range
        min_from_date = to_date - @days_back.days

        # Determine fetch strategy:
        # - If latest candle is within days_back window: incremental update (fetch from latest + 1 day)
        # - If latest candle is older than days_back: gap fill (fetch from min_from_date)
        if latest_date >= min_from_date
          # Incremental update: latest candle is recent, fetch only new data
          from_date = latest_date
          Rails.logger.debug do
            "[Candles::DailyIngestor] #{instrument.symbol_name}: " \
              "Incremental update (latest: #{latest_date}, fetching from: #{from_date})"
          end
        else
          # Gap fill: latest candle is very old, fetch from minimum required date
          from_date = min_from_date
          gap_days = (to_date - latest_date - 1).to_i
          Rails.logger.info do
            "[Candles::DailyIngestor] #{instrument.symbol_name}: " \
              "Gap detected (latest: #{latest_date}, gap: #{gap_days} days, fetching from: #{from_date})"
          end
        end
      else
        # No existing candles - fetch full range
        from_date = to_date - @days_back.days
      end

      # Fetch historical daily candles from DhanHQ (only for the optimized date range)
      candles_data = fetch_daily_candles(
        instrument: instrument,
        from_date: from_date,
        to_date: to_date,
      )

      return { success: false, error: "No candles data received" } if candles_data.blank?

      # Upsert candles to database (will skip existing ones)
      result = Ingestor.upsert_candles(
        instrument: instrument,
        timeframe: :daily,
        candles_data: candles_data,
      )

      if result[:success]
        action_type = latest_candle ? "updated" : "initial_load"
        Rails.logger.info(
          "[Candles::DailyIngestor] #{instrument.symbol_name} (#{action_type}): " \
          "upserted=#{result[:upserted]}, skipped=#{result[:skipped]}, total=#{result[:total]}, " \
          "date_range=#{from_date}..#{to_date}",
        )
      end

      result
    rescue StandardError => e
      error_msg = e.message.to_s
      is_rate_limit = error_msg.include?("429") || error_msg.include?("rate limit") || error_msg.include?("Rate limit") || error_msg.include?("too many requests") || error_msg.include?("DH-904") || e.class.name == "DhanHQ::RateLimitError"

      # Re-raise rate limit errors so they can be retried by fetch_and_store_daily_candles_with_retry
      if is_rate_limit
        Rails.logger.warn("[Candles::DailyIngestor] Rate limit error for #{instrument&.symbol_name}, will retry")
        raise
      end

      error_msg = "Failed to fetch daily candles for #{instrument&.symbol_name}: #{error_msg}"
      Rails.logger.error("[Candles::DailyIngestor] #{error_msg}")
      { success: false, error: error_msg }
    end

    def fetch_and_store_daily_candles_with_retry(instrument)
      retries = 0
      begin
        result = fetch_and_store_daily_candles(instrument)
        result[:retries] = retries
        result
      rescue StandardError => e
        error_msg = e.message.to_s
        is_rate_limit = error_msg.include?("429") || error_msg.include?("rate limit") || error_msg.include?("Rate limit") || error_msg.include?("too many requests")

        if is_rate_limit && retries < MAX_RETRIES
          retries += 1
          delay = INITIAL_RETRY_DELAY * (2**(retries - 1)) # Exponential backoff: 2s, 4s, 8s
          Rails.logger.warn(
            "[Candles::DailyIngestor] Rate limit hit for #{instrument.symbol_name}, " \
            "retrying in #{delay}s (attempt #{retries}/#{MAX_RETRIES})",
          )
          sleep(delay)
          retry
        else
          { success: false, error: error_msg, retries: retries }
        end
      end
    end

    def fetch_daily_candles(instrument:, from_date:, to_date:)
      # Use Instrument's historical_ohlc method (already implemented in InstrumentHelpers)
      instrument.historical_ohlc(from_date: from_date, to_date: to_date, oi: false)
    rescue StandardError => e
      error_msg = e.message.to_s
      is_rate_limit = error_msg.include?("429") || error_msg.include?("rate limit") || error_msg.include?("Rate limit")

      if is_rate_limit
        Rails.logger.warn(
          "[Candles::DailyIngestor] Rate limit error for #{instrument.symbol_name}",
        )
        # Re-raise to trigger retry logic
        raise
      else
        Rails.logger.error(
          "[Candles::DailyIngestor] DhanHQ API error for #{instrument.symbol_name}: #{error_msg}",
        )
        nil
      end
    end

    def log_summary(results, duration)
      puts "\n✅ Daily candle ingestion completed!"
      puts "   Duration: #{(duration / 60).round(1)} minutes"
      puts "   Processed: #{results[:processed]}"
      puts "   Success: #{results[:success]}"
      puts "   Failed: #{results[:failed]}"
      puts "   Already up-to-date: #{results[:skipped_up_to_date]}" if results[:skipped_up_to_date].positive?
      puts "   Skipped (time window): #{results[:skipped_time_window]}" if results[:skipped_time_window].positive?
      puts "   Total candles: #{results[:total_candles]}"
      puts "   Rate limit retries: #{results[:rate_limit_retries]}" if results[:rate_limit_retries].positive?

      Rails.logger.info(
        "[Candles::DailyIngestor] Summary: " \
        "processed=#{results[:processed]}, " \
        "success=#{results[:success]}, " \
        "failed=#{results[:failed]}, " \
        "skipped_up_to_date=#{results[:skipped_up_to_date]}, " \
        "skipped_time_window=#{results[:skipped_time_window]}, " \
        "total_candles=#{results[:total_candles]}, " \
        "duration=#{duration.round(2)}s, " \
        "rate_limit_retries=#{results[:rate_limit_retries]}",
      )

      return unless results[:errors].any?

      puts "\n⚠️  Errors encountered (#{results[:errors].size}):"
      results[:errors].first(10).each do |error|
        puts "   - #{error[:instrument]}: #{error[:error][0..100]}"
      end

      Rails.logger.warn(
        "[Candles::DailyIngestor] Errors (#{results[:errors].size}): " \
        "#{results[:errors].first(5).pluck(:instrument).join(', ')}",
      )
    end
  end
end
