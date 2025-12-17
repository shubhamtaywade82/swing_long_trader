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

      # Calculate date range
      to_date = Time.zone.today - 1 # Yesterday (today's data may not be complete)

      # Check for existing candles to optimize date range
      latest_candle = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: "1D")

      if latest_candle
        # Start from the day after the latest candle (optimization: only fetch new data)
        latest_date = latest_candle.timestamp.to_date
        from_date = latest_date + 1.day

        # If we already have data up to yesterday, skip this instrument
        if from_date > to_date
          Rails.logger.debug do
            "[Candles::DailyIngestor] #{instrument.symbol_name}: " \
              "Already up-to-date (latest: #{latest_date}, to_date: #{to_date})"
          end
          return {
            success: true,
            upserted: 0,
            skipped: 0,
            total: 0,
            action: :skipped_up_to_date,
          }
        end

        # Ensure we don't fetch less than minimum required days (for initial gaps)
        # If latest candle is very old (older than min_from_date), fetch from min_from_date to fill gaps
        # Otherwise, fetch from the day after latest candle (incremental update)
        min_from_date = to_date - @days_back.days
        from_date = [from_date, min_from_date].max
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
        timeframe: "1D",
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
      error_msg = "Failed to fetch daily candles for #{instrument&.symbol_name}: #{e.message}"
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
      puts "   Total candles: #{results[:total_candles]}"
      puts "   Rate limit retries: #{results[:rate_limit_retries]}" if results[:rate_limit_retries].positive?

      Rails.logger.info(
        "[Candles::DailyIngestor] Summary: " \
        "processed=#{results[:processed]}, " \
        "success=#{results[:success]}, " \
        "failed=#{results[:failed]}, " \
        "skipped_up_to_date=#{results[:skipped_up_to_date]}, " \
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
