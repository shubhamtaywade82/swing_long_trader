# frozen_string_literal: true

module Candles
  # Fetches intraday candles on-demand (in-memory only, no DB storage)
  # Used for real-time analysis and screening
  class IntradayFetcher < ApplicationService
    SUPPORTED_INTERVALS = %w[15 60 120].freeze # 15min, 1hr, 2hr
    DEFAULT_INTERVAL = '15'
    DEFAULT_DAYS = 2

    def self.call(instrument:, interval: DEFAULT_INTERVAL, days: DEFAULT_DAYS, cache: true)
      new(instrument: instrument, interval: interval, days: days, cache: cache).call
    end

    def initialize(instrument:, interval: DEFAULT_INTERVAL, days: DEFAULT_DAYS, cache: true)
      @instrument = instrument
      @interval = interval.to_s
      @days = days
      @cache = cache
    end

    def call
      return { success: false, error: 'Invalid instrument' } unless @instrument.present?
      return { success: false, error: 'Invalid interval' } unless SUPPORTED_INTERVALS.include?(@interval)

      # Check cache first
      if @cache
        cached_data = fetch_from_cache
        return { success: true, candles: cached_data, cached: true } if cached_data.present?
      end

      # Fetch from API
      candles_data = fetch_intraday_candles

      return { success: false, error: 'No candles data received' } if candles_data.blank?

      # Normalize candles
      normalized = normalize_candles(candles_data)

      # Cache the result
      cache_result(normalized) if @cache && normalized.any?

      {
        success: true,
        candles: normalized,
        cached: false,
        count: normalized.size
      }
    rescue StandardError => e
      error_msg = "Failed to fetch intraday candles for #{@instrument&.symbol_name}: #{e.message}"
      Rails.logger.error("[Candles::IntradayFetcher] #{error_msg}")
      { success: false, error: error_msg }
    end

    private

    def fetch_intraday_candles
      # Calculate date range
      to_date = Time.zone.today
      from_date = to_date - @days.days

      # Use Instrument's intraday_ohlc method
      @instrument.intraday_ohlc(
        interval: @interval,
        oi: false,
        from_date: from_date.to_s,
        to_date: to_date.to_s,
        days: @days
      )
    rescue StandardError => e
      Rails.logger.error(
        "[Candles::IntradayFetcher] DhanHQ API error for #{@instrument.symbol_name}: #{e.message}"
      )
      nil
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
      Rails.logger.warn("[Candles::IntradayFetcher] Failed to normalize candle: #{e.message}")
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

    def cache_key
      "intraday_candles:#{@instrument.id}:#{@interval}:#{@days}"
    end

    def fetch_from_cache
      cached = Rails.cache.read(cache_key)
      return nil unless cached

      # Check if cache is still valid (TTL: 5 minutes for intraday data)
      cached
    end

    def cache_result(candles)
      # Cache for 5 minutes (intraday data changes frequently)
      Rails.cache.write(cache_key, candles, expires_in: 5.minutes)
    end
  end
end

