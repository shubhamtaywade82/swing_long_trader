# frozen_string_literal: true

module Api
  module V1
    # High-performance API endpoint for bulk LTP retrieval
    # Reads multiple LTPs from Redis in a single round trip using MGET
    class CurrentPricesController < ApplicationController
      # Skip CSRF protection for API endpoint
      skip_before_action :verify_authenticity_token, if: :json_request?

      # POST /api/v1/current_prices (with keys in body) or GET /api/v1/current_prices?keys=... (for small requests)
      def index
        # Support both POST (body) and GET (query string) for flexibility
        if request.post?
          # POST: keys in request body as JSON array or comma-separated string
          begin
            parsed_body = request.content_type&.include?("json") ? JSON.parse(request.raw_post) : {}
            keys_param = parsed_body["keys"] || params[:keys] || ""
          rescue JSON::ParserError
            keys_param = params[:keys].to_s
          end
        else
          # GET: keys in query string (for small requests)
          keys_param = params[:keys].to_s
        end

        return render_error("Missing 'keys' parameter") if keys_param.blank?

        # Parse keys: "NSE_EQ:1333,NSE_EQ:11536" or ["NSE_EQ:1333", "NSE_EQ:11536"] -> array
        instrument_keys = if keys_param.is_a?(Array)
                            keys_param.map(&:to_s).map(&:strip).reject(&:blank?)
                          else
                            keys_param.to_s.split(",").map(&:strip).reject(&:blank?)
                          end
        return render_error("No valid keys provided") if instrument_keys.empty?

        # Build Redis keys with prefix
        redis_keys = instrument_keys.map { |k| "ltp:#{k}" }

        # Fetch all LTPs from Redis cache (websocket cached values)
        prices = fetch_prices_from_redis(redis_keys)

        # Build initial result hash from cache: "NSE_EQ:1333" => 1234.56
        result = {}
        missing_keys = []
        instrument_keys.each_with_index do |key, index|
          price_value = prices[index]
          if price_value
            result[key] = price_value.to_f
          else
            result[key] = nil
            missing_keys << key
          end
        end

        # Fallback to MarketFeed.ltp API for missing values (if websocket not available)
        fetched_ltps = {}
        if missing_keys.any?
          fetched_ltps = fetch_missing_ltps_from_api(missing_keys)
          fetched_ltps.each do |key, price|
            result[key] = price if price
            # Cache the fetched value in Redis for future requests
            cache_key = "ltp:#{key}"
            redis_client.setex(cache_key, 30, price.to_s) if redis_client.respond_to?(:setex) && price
          end
        end

        render json: {
          prices: result,
          timestamp: Time.current.iso8601,
          count: result.size,
          cached_count: result.values.count { |v| !v.nil? },
          api_fetched_count: fetched_ltps.size,
        }
      rescue StandardError => e
        Rails.logger.error("[Api::V1::CurrentPricesController] Error: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        render_error("Internal server error: #{e.message}")
      end

      private

      def fetch_prices_from_redis(keys)
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

      # Fetch missing LTPs from MarketFeed.ltp API (fallback when websocket not available)
      # @param missing_keys [Array<String>] Array of keys in format "SEGMENT:SECURITY_ID"
      # @return [Hash<String, Float>] Hash of key => price
      def fetch_missing_ltps_from_api(missing_keys)
        return {} if missing_keys.empty?

        # Parse keys and group by segment: { "NSE_EQ" => [1333, 11536, ...] }
        grouped_by_segment = {}
        missing_keys.each do |key|
          segment, security_id = key.split(":", 2)
          next unless segment && security_id

          segment = segment.to_s.upcase
          grouped_by_segment[segment] ||= []
          grouped_by_segment[segment] << security_id.to_i
        end

        return {} if grouped_by_segment.empty?

        # Fetch LTPs from MarketFeed API for each segment
        fetched_ltps = {}
        grouped_by_segment.each do |segment, security_ids|
          payload = { segment => security_ids.uniq }
          response = DhanHQ::Models::MarketFeed.ltp(payload)

          next unless response.is_a?(Hash) && response["status"] == "success"

          # Parse response: { "data" => { "NSE_EQ" => { "1333" => { "last_price" => 1234.56 } } } }
          segment_data = response.dig("data", segment) || {}
          segment_data.each do |security_id_str, price_data|
            last_price = price_data&.dig("last_price")
            next unless last_price

            key = "#{segment}:#{security_id_str}"
            fetched_ltps[key] = last_price.to_f
          end
        rescue StandardError => e
          # Suppress 429 rate limit errors (expected during high load)
          error_msg = e.message.to_s
          is_rate_limit = error_msg.include?("429") || error_msg.include?("rate limit") || error_msg.include?("Rate limit")
          unless is_rate_limit
            Rails.logger.warn("[Api::V1::CurrentPricesController] Failed to fetch LTPs from API for segment #{segment}: #{error_msg}")
          end
        end

        fetched_ltps
      end

      def redis_client
        # Try to use Redis directly if available
        @redis_client ||= if defined?(Redis) && ENV["REDIS_URL"].present?
                            Redis.new(url: ENV.fetch("REDIS_URL", nil))
                          elsif Rails.cache.respond_to?(:redis)
                            Rails.cache.redis
                          else
                            # Fallback to Rails.cache (doesn't support MGET, but works)
                            Rails.cache
                          end
      end

      def render_error(message, status: :bad_request)
        render json: {
          error: message,
          timestamp: Time.current.iso8601,
        }, status: status
      end

      def json_request?
        request.format.json?
      end
    end
  end
end
