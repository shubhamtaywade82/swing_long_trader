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

# Module-level variable to store listener reference for graceful shutdown
module MarketHub
  @ltp_pubsub_listener = nil

  class << self
    attr_accessor :ltp_pubsub_listener
  end
end

# Use to_prepare to ensure classes are loaded (runs after autoloading)
Rails.application.config.to_prepare do
  # Skip in test environment to avoid interference with tests
  next if Rails.env.test?

  # Only start if Redis is available
  unless defined?(Redis) && ENV["REDIS_URL"].present?
    Rails.logger.info("[LtpPubSubListener] Redis not configured, skipping Pub/Sub listener initialization")
    next
  end

  # Only start once (check if already started)
  next if MarketHub.ltp_pubsub_listener&.running?

  begin
    listener = MarketHub::LtpPubSubListener.new
    listener.start

    # Store reference for graceful shutdown
    MarketHub.ltp_pubsub_listener = listener

    Rails.logger.info("[LtpPubSubListener] Initialized Redis Pub/Sub listener for broker-style LTP updates")
  rescue NameError => e
    Rails.logger.error("[LtpPubSubListener] Service class not found: #{e.message}")
    Rails.logger.error("Make sure app/services/market_hub/ltp_pubsub_listener.rb exists and MarketHub module is defined")
  rescue StandardError => e
    Rails.logger.error("[LtpPubSubListener] Failed to initialize: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
  end
end

# Graceful shutdown: Stop listener on application exit
at_exit do
  listener = MarketHub.ltp_pubsub_listener
  if listener&.respond_to?(:stop)
    Rails.logger.info("[LtpPubSubListener] Stopping Redis Pub/Sub listener on application exit")
    listener.stop
  end
end
