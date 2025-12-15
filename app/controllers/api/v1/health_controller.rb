# frozen_string_literal: true

module Api
  module V1
    # Health check endpoint for market stream service
    class HealthController < ApplicationController
      skip_before_action :verify_authenticity_token, if: :json_request?

      # GET /api/v1/health/market_stream
      def market_stream
        # Check if market stream heartbeat exists in Redis
        heartbeat_key = "market_stream:heartbeat"
        heartbeat_timestamp = redis_client.read(heartbeat_key)

        if heartbeat_timestamp
          heartbeat_time = Time.at(heartbeat_timestamp.to_i)
          age_seconds = Time.current - heartbeat_time

          render json: {
            status: age_seconds < 60 ? "healthy" : "stale",
            heartbeat_age_seconds: age_seconds.round(1),
            heartbeat_timestamp: heartbeat_time.iso8601,
            timestamp: Time.current.iso8601,
          }
        else
          render json: {
            status: "not_running",
            message: "Market stream service heartbeat not found",
            timestamp: Time.current.iso8601,
          }, status: :service_unavailable
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
