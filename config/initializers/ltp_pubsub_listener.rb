# frozen_string_literal: true

require "redis" unless defined?(Redis)

# Initialize Redis Pub/Sub listener for broker-style LTP updates
# This listener subscribes to Redis Pub/Sub channel and broadcasts updates via ActionCable
#
# Architecture:
# 1. WebSocket worker (WebsocketTickStreamer) publishes ticks to Redis Pub/Sub
# 2. This listener subscribes to Pub/Sub and broadcasts to ActionCable
# 3. Multiple Rails instances can subscribe to the same Pub/Sub channel
#
# The listener runs in a background thread and automatically starts on Rails boot
# (only in production/development, skipped in test environment)

Rails.application.config.after_initialize do
  # Skip in test environment to avoid interference with tests
  next if Rails.env.test?

  # Only start if Redis is available
  unless defined?(Redis) && ENV["REDIS_URL"].present?
    Rails.logger.info("[LtpPubSubListener] Redis not configured, skipping Pub/Sub listener initialization")
    next
  end

  begin
    listener = MarketHub::LtpPubSubListener.new
    listener.start

    # Store reference for graceful shutdown
    Rails.application.config.ltp_pubsub_listener = listener

    Rails.logger.info("[LtpPubSubListener] Initialized Redis Pub/Sub listener for broker-style LTP updates")
  rescue StandardError => e
    Rails.logger.error("[LtpPubSubListener] Failed to initialize: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
  end
end

# Graceful shutdown: Stop listener on application exit
Rails.application.config.to_prepare do
  at_exit do
    listener = Rails.application.config.ltp_pubsub_listener
    if listener&.respond_to?(:stop)
      Rails.logger.info("[LtpPubSubListener] Stopping Redis Pub/Sub listener on application exit")
      listener.stop
    end
  end
end
