# frozen_string_literal: true

module Candles
  class DailyIngestor < ApplicationService
    DEFAULT_DAYS_BACK = 365

    def self.call(instruments: nil, days_back: nil)
      new(instruments: instruments, days_back: days_back).call
    end

    def initialize(instruments: nil, days_back: nil)
      @instruments = instruments || Instrument.where(instrument_type: ['EQUITY', 'INDEX'])
      @days_back = days_back || DEFAULT_DAYS_BACK
    end

    def call
      results = {
        processed: 0,
        success: 0,
        failed: 0,
        total_candles: 0,
        errors: []
      }

      @instruments.find_each(batch_size: 100) do |instrument|
        result = fetch_and_store_daily_candles(instrument)
        results[:processed] += 1

        if result[:success]
          results[:success] += 1
          results[:total_candles] += result[:upserted] || 0
        else
          results[:failed] += 1
          results[:errors] << { instrument: instrument.symbol_name, error: result[:error] }
        end

        # Rate limiting: small delay to avoid API throttling
        sleep(0.1) if results[:processed] % 10 == 0
      end

      log_summary(results)
      results
    end

    private

    def fetch_and_store_daily_candles(instrument)
      return { success: false, error: 'Invalid instrument' } unless instrument.present?
      return { success: false, error: 'Missing security_id' } unless instrument.security_id.present?

      # Calculate date range
      to_date = Time.zone.today - 1 # Yesterday (today's data may not be complete)
      from_date = to_date - @days_back.days

      # Fetch historical daily candles from DhanHQ
      candles_data = fetch_daily_candles(
        instrument: instrument,
        from_date: from_date,
        to_date: to_date
      )

      return { success: false, error: 'No candles data received' } if candles_data.blank?

      # Upsert candles to database
      result = Ingestor.upsert_candles(
        instrument: instrument,
        timeframe: '1D',
        candles_data: candles_data
      )

      if result[:success]
        Rails.logger.info(
          "[Candles::DailyIngestor] #{instrument.symbol_name}: " \
          "upserted=#{result[:upserted]}, skipped=#{result[:skipped]}, total=#{result[:total]}"
        )
      end

      result
    rescue StandardError => e
      error_msg = "Failed to fetch daily candles for #{instrument&.symbol_name}: #{e.message}"
      Rails.logger.error("[Candles::DailyIngestor] #{error_msg}")
      { success: false, error: error_msg }
    end

    def fetch_daily_candles(instrument:, from_date:, to_date:)
      # Use Instrument's historical_ohlc method (already implemented in InstrumentHelpers)
      instrument.historical_ohlc(from_date: from_date, to_date: to_date, oi: false)
    rescue StandardError => e
      Rails.logger.error(
        "[Candles::DailyIngestor] DhanHQ API error for #{instrument.symbol_name}: #{e.message}"
      )
      nil
    end

    def log_summary(results)
      Rails.logger.info(
        "[Candles::DailyIngestor] Summary: " \
        "processed=#{results[:processed]}, " \
        "success=#{results[:success]}, " \
        "failed=#{results[:failed]}, " \
        "total_candles=#{results[:total_candles]}"
      )

      if results[:errors].any?
        Rails.logger.warn(
          "[Candles::DailyIngestor] Errors (#{results[:errors].size}): " \
          "#{results[:errors].first(5).map { |e| e[:instrument] }.join(', ')}"
        )
      end
    end
  end
end

