# frozen_string_literal: true

module MarketData
  # Service to access cached LTPs (Last Traded Prices) from Redis
  # LTPs are cached by the WebSocket streaming service with key format: ltp:SEGMENT:SECURITY_ID
  #
  # Usage:
  #   # Get single LTP
  #   price = MarketData::LtpCache.get("NSE_EQ", "1333")
  #   # => 1234.56 or nil if not cached
  #
  #   # Get multiple LTPs (efficient - uses MGET)
  #   prices = MarketData::LtpCache.get_multiple([
  #     ["NSE_EQ", "1333"],
  #     ["NSE_EQ", "11536"]
  #   ])
  #   # => { "NSE_EQ:1333" => 1234.56, "NSE_EQ:11536" => 5678.90 }
  #
  #   # Get LTP by instrument
  #   instrument = Instrument.find(1)
  #   price = MarketData::LtpCache.get_by_instrument(instrument)
  #
  #   # Get LTPs for multiple instruments
  #   instruments = Instrument.where(id: [1, 2, 3])
  #   prices = MarketData::LtpCache.get_by_instruments(instruments)
  #   # => { 1 => 1234.56, 2 => 5678.90, 3 => nil }
  class LtpCache
    LTP_KEY_PREFIX = "ltp"

    class << self
      # Get LTP for a single instrument by segment and security_id
      # @param segment [String] Exchange segment (e.g., "NSE_EQ")
      # @param security_id [String, Integer] Security ID (e.g., "1333")
      # @return [Float, nil] LTP value or nil if not cached
      def get(segment, security_id)
        key = build_key(segment, security_id)
        value = if redis_client.respond_to?(:get)
                  redis_client.get(key)
                else
                  redis_client.read(key)
                end
        value ? value.to_f : nil
      end

      # Get multiple LTPs efficiently using Redis MGET
      # @param instruments [Array<Array<String, String>>] Array of [segment, security_id] pairs
      # @return [Hash<String, Float>] Hash with keys like "NSE_EQ:1333" => 1234.56
      def get_multiple(instruments)
        return {} if instruments.empty?

        # Build Redis keys
        redis_keys = instruments.map { |segment, security_id| build_key(segment, security_id) }
        instrument_keys = instruments.map { |segment, security_id| "#{segment}:#{security_id}" }

        # Fetch from Redis
        values = fetch_from_redis(redis_keys)

        # Build result hash
        result = {}
        instrument_keys.each_with_index do |key, index|
          value = values[index]
          result[key] = value ? value.to_f : nil
        end

        result
      end

      # Get LTP by Instrument model
      # @param instrument [Instrument] Instrument model instance
      # @return [Float, nil] LTP value or nil if not cached
      def get_by_instrument(instrument)
        return nil unless instrument

        get(instrument.exchange_segment, instrument.security_id)
      end

      # Get LTPs for multiple Instrument models
      # @param instruments [ActiveRecord::Relation, Array<Instrument>] Collection of instruments
      # @return [Hash<Integer, Float>] Hash with instrument_id => LTP value
      def get_by_instruments(instruments)
        return {} if instruments.blank?

        # Convert to [segment, security_id] pairs with instrument_id mapping
        instrument_pairs = instruments.map do |instrument|
          [instrument.exchange_segment, instrument.security_id.to_s, instrument.id]
        end

        # Build Redis keys and maintain mapping
        redis_keys = instrument_pairs.map { |segment, security_id, _id| build_key(segment, security_id) }
        id_mapping = instrument_pairs.map { |_segment, _security_id, id| id }

        # Fetch from Redis
        values = fetch_from_redis(redis_keys)

        # Build result hash with instrument_id as key
        result = {}
        id_mapping.each_with_index do |instrument_id, index|
          value = values[index]
          result[instrument_id] = value ? value.to_f : nil
        end

        result
      end

      # Check if LTP is cached for an instrument
      # @param segment [String] Exchange segment
      # @param security_id [String, Integer] Security ID
      # @return [Boolean] True if LTP is cached
      def cached?(segment, security_id)
        key = build_key(segment, security_id)
        redis_client.exist?(key)
      end

      # Get all cached LTPs (use with caution - can be slow for large datasets)
      # @param pattern [String] Optional Redis key pattern (default: "ltp:*")
      # @return [Hash<String, Float>] Hash with keys like "NSE_EQ:1333" => 1234.56
      def get_all(pattern: nil)
        pattern ||= "#{LTP_KEY_PREFIX}:*"

        if redis_client.respond_to?(:keys)
          keys = redis_client.keys(pattern)
          return {} if keys.empty?

          values = fetch_from_redis(keys)
          result = {}
          keys.each_with_index do |key, index|
            # Extract segment:security_id from key (remove "ltp:" prefix)
            instrument_key = key.gsub(/^#{LTP_KEY_PREFIX}:/o, "")
            value = values[index]
            result[instrument_key] = value ? value.to_f : nil
          end
          result
        else
          # Fallback: can't efficiently get all keys with Rails.cache
          Rails.logger.warn("[MarketData::LtpCache] get_all not supported with Rails.cache, use Redis")
          {}
        end
      end

      # Get cache statistics
      # @return [Hash] Statistics about cached LTPs
      def stats
        if redis_client.respond_to?(:keys)
          keys = redis_client.keys("#{LTP_KEY_PREFIX}:*")
          {
            total_cached: keys.size,
            cache_prefix: LTP_KEY_PREFIX,
            redis_available: true,
          }
        else
          {
            total_cached: 0,
            cache_prefix: LTP_KEY_PREFIX,
            redis_available: false,
            message: "Redis not available, using Rails.cache (stats not available)",
          }
        end
      rescue StandardError => e
        {
          error: e.message,
          redis_available: false,
        }
      end

      private

      def build_key(segment, security_id)
        "#{LTP_KEY_PREFIX}:#{segment}:#{security_id}"
      end

      def fetch_from_redis(keys)
        if redis_client.respond_to?(:mget)
          # Use Redis MGET for maximum performance (single round trip)
          redis_client.mget(*keys)
        else
          # Fallback: fetch individually (slower but works with Rails.cache)
          keys.map do |key|
            if redis_client.respond_to?(:get)
              redis_client.get(key)
            else
              redis_client.read(key)
            end
          end
        end
      end

      def redis_client
        # Try to use Redis directly if available
        @redis_client ||= if defined?(Redis) && ENV["REDIS_URL"].present?
                            Redis.new(url: ENV.fetch("REDIS_URL", nil))
                          elsif Rails.cache.respond_to?(:redis)
                            Rails.cache.redis
                          else
                            # Fallback to Rails.cache (doesn't support MGET efficiently, but works)
                            Rails.cache
                          end
      end
    end
  end
end
