# frozen_string_literal: true

module Api
  module V1
    # High-performance API endpoint for bulk LTP retrieval
    # Reads multiple LTPs from Redis in a single round trip using MGET
    class CurrentPricesController < ApplicationController
      # Skip CSRF protection for API endpoint
      skip_before_action :verify_authenticity_token, if: :json_request?

      # GET /api/v1/current_prices?keys=NSE_EQ:1333,NSE_EQ:11536
      def index
        keys_param = params[:keys].to_s
        return render_error("Missing 'keys' parameter") if keys_param.blank?

        # Parse keys: "NSE_EQ:1333,NSE_EQ:11536" -> ["ltp:NSE_EQ:1333", "ltp:NSE_EQ:11536"]
        instrument_keys = keys_param.split(",").map(&:strip).reject(&:blank?)
        return render_error("No valid keys provided") if instrument_keys.empty?

        # Build Redis keys with prefix
        redis_keys = instrument_keys.map { |k| "ltp:#{k}" }

        # Fetch all LTPs in a single Redis MGET operation
        prices = fetch_prices_from_redis(redis_keys)

        # Build response hash: "NSE_EQ:1333" => 1234.56
        result = {}
        instrument_keys.each_with_index do |key, index|
          price_value = prices[index]
          result[key] = price_value ? price_value.to_f : nil
        end

        render json: {
          prices: result,
          timestamp: Time.current.iso8601,
          count: result.size,
          cached_count: result.values.count { |v| !v.nil? },
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
          keys.map { |key| redis_client.read(key) }
        end
      end

      def redis_client
        @redis_client ||= begin
          # Try to use Redis directly if available
          if defined?(Redis) && ENV["REDIS_URL"].present?
            Redis.new(url: ENV["REDIS_URL"])
          elsif Rails.cache.respond_to?(:redis)
            Rails.cache.redis
          else
            # Fallback to Rails.cache (doesn't support MGET, but works)
            Rails.cache
          end
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
