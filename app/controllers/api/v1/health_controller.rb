# frozen_string_literal: true

module Api
  module V1
    # Health check endpoint for market stream service
    class HealthController < ApplicationController
      skip_before_action :verify_authenticity_token, if: :json_request?

      # GET /api/v1/health/market_stream
      def market_stream
        # Check for active WebSocket streams using existing cache mechanism
        # Look for websocket_stream:* cache entries
        stream_keys = find_active_stream_keys

        if stream_keys.any?
          # Get the most recent heartbeat
          latest_heartbeat = stream_keys.map do |stream_key|
            cache_key = "websocket_stream:#{stream_key}"
            cache_data = Rails.cache.read(cache_key)
            next unless cache_data.is_a?(Hash)

            heartbeat = cache_data[:heartbeat]
            next unless heartbeat

            Time.parse(heartbeat.to_s) rescue nil
          end.compact.max

          if latest_heartbeat
            age_seconds = Time.current - latest_heartbeat
            render json: {
              status: age_seconds < 2.minutes ? "healthy" : "stale",
              heartbeat_age_seconds: age_seconds.round(1),
              heartbeat_timestamp: latest_heartbeat.iso8601,
              active_streams: stream_keys.size,
              stream_keys: stream_keys,
              timestamp: Time.current.iso8601,
            }
          else
            render json: {
              status: "no_heartbeat",
              message: "Streams found but no valid heartbeat",
              active_streams: stream_keys.size,
              timestamp: Time.current.iso8601,
            }
          end
        else
          # Fallback: check Redis heartbeat (for backward compatibility)
          heartbeat_key = "market_stream:heartbeat"
          heartbeat_timestamp = redis_client.read(heartbeat_key)

          if heartbeat_timestamp
            heartbeat_time = Time.at(heartbeat_timestamp.to_i)
            age_seconds = Time.current - heartbeat_time

            render json: {
              status: age_seconds < 60 ? "healthy" : "stale",
              heartbeat_age_seconds: age_seconds.round(1),
              heartbeat_timestamp: heartbeat_time.iso8601,
              source: "redis_heartbeat",
              timestamp: Time.current.iso8601,
            }
          else
            render json: {
              status: "not_running",
              message: "No active WebSocket streams found",
              timestamp: Time.current.iso8601,
            }, status: :service_unavailable
          end
        end
      rescue StandardError => e
        Rails.logger.error("[Api::V1::HealthController] Error: #{e.message}")
        render json: {
          status: "error",
          error: e.message,
          timestamp: Time.current.iso8601,
        }, status: :internal_server_error
      end

      private

      def find_active_stream_keys
        # Find all active stream cache keys
        # This is approximate - in production you might want a more sophisticated tracking mechanism
        keys = []
        
        # Check common stream key patterns
        ["type:swing", "type:longterm", "default"].each do |prefix|
          cache_key = "websocket_stream:#{prefix}"
          cache_data = Rails.cache.read(cache_key)
          if cache_data.is_a?(Hash) && cache_data[:status] == "running"
            keys << prefix
          end
        end

        keys
      end

      def redis_client
        @redis_client ||= begin
          if defined?(Redis) && ENV["REDIS_URL"].present?
            Redis.new(url: ENV["REDIS_URL"])
          elsif Rails.cache.respond_to?(:redis)
            Rails.cache.redis
          else
            Rails.cache
          end
        end
      end

      def json_request?
        request.format.json?
      end
    end
  end
end
