# frozen_string_literal: true

require "redis" unless defined?(Redis)

module MarketHub
  # Service to subscribe to Redis Pub/Sub channel and broadcast LTP updates via ActionCable
  # This implements the broker-style architecture where:
  # 1. WebSocket worker publishes ticks to Redis Pub/Sub
  # 2. This listener subscribes to Pub/Sub and broadcasts to ActionCable
  # 3. Multiple Rails instances can subscribe to the same Pub/Sub channel
  #
  # Usage:
  #   listener = MarketHub::LtpPubSubListener.new
  #   listener.start # Starts subscription in background thread
  #   listener.stop  # Stops subscription gracefully
  class LtpPubSubListener
    PUBSUB_CHANNEL = "live_ltp_updates"
    THREAD_NAME = "LtpPubSubListener"

    def initialize
      @subscription_thread = nil
      @running = false
      @redis_subscriber = nil
    end

    # Start subscribing to Redis Pub/Sub channel
    # Runs in a background thread to avoid blocking
    def start
      return if @running

      Rails.logger.info("[MarketHub::LtpPubSubListener] Starting Redis Pub/Sub listener for channel: #{PUBSUB_CHANNEL}")

      unless redis_available?
        Rails.logger.warn("[MarketHub::LtpPubSubListener] Redis not available, skipping Pub/Sub listener")
        return false
      end

      @running = true
      @subscription_thread = Thread.new do
        Thread.current.name = THREAD_NAME
        Thread.current.abort_on_exception = false # Handle errors gracefully

        begin
          subscribe_to_channel
        rescue StandardError => e
          Rails.logger.error("[MarketHub::LtpPubSubListener] Thread error: #{e.message}")
          Rails.logger.error(e.backtrace.first(10).join("\n"))
          @running = false
        end
      end

      Rails.logger.info("[MarketHub::LtpPubSubListener] Started Pub/Sub listener thread: #{@subscription_thread.name}")
      true
    end

    # Stop subscribing and cleanup
    def stop
      return unless @running

      Rails.logger.info("[MarketHub::LtpPubSubListener] Stopping Redis Pub/Sub listener")

      @running = false

      # Unsubscribe from Redis channel
      begin
        @redis_subscriber&.unsubscribe(PUBSUB_CHANNEL)
        @redis_subscriber&.quit
      rescue StandardError => e
        Rails.logger.warn("[MarketHub::LtpPubSubListener] Error unsubscribing: #{e.message}")
      ensure
        @redis_subscriber = nil
      end

      # Wait for thread to finish (with timeout)
      if @subscription_thread&.alive?
        @subscription_thread.join(5) # Wait up to 5 seconds
        @subscription_thread.kill if @subscription_thread.alive? # Force kill if still alive
      end

      @subscription_thread = nil
      Rails.logger.info("[MarketHub::LtpPubSubListener] Stopped Pub/Sub listener")
    end

    # Check if listener is running
    def running?
      @running && @subscription_thread&.alive?
    end

    private

    def subscribe_to_channel
      # Create a dedicated Redis connection for Pub/Sub (required by Redis)
      # Pub/Sub connections must be separate from regular Redis connections
      redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
      @redis_subscriber = Redis.new(url: redis_url)

      Rails.logger.info("[MarketHub::LtpPubSubListener] Connected to Redis, subscribing to channel: #{PUBSUB_CHANNEL}")

      # Subscribe to channel and listen for messages
      @redis_subscriber.subscribe(PUBSUB_CHANNEL) do |on|
        on.message do |channel, message|
          next unless @running # Stop processing if stopped

          begin
            handle_message(message)
          rescue StandardError => e
            Rails.logger.error("[MarketHub::LtpPubSubListener] Error handling message: #{e.message}")
            Rails.logger.error("Message: #{message.inspect}")
            Rails.logger.error(e.backtrace.first(5).join("\n"))
          end
        end

        on.subscribe do |channel, subscriptions|
          Rails.logger.info("[MarketHub::LtpPubSubListener] Subscribed to channel: #{channel} (total subscriptions: #{subscriptions})")
        end

        on.unsubscribe do |channel, subscriptions|
          Rails.logger.info("[MarketHub::LtpPubSubListener] Unsubscribed from channel: #{channel} (remaining subscriptions: #{subscriptions})")
        end
      end
    rescue Redis::ConnectionError => e
      Rails.logger.error("[MarketHub::LtpPubSubListener] Redis connection error: #{e.message}")
      @running = false
    rescue StandardError => e
      Rails.logger.error("[MarketHub::LtpPubSubListener] Subscription error: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      @running = false
    end

    def handle_message(message)
      # Parse JSON message from WebSocket worker
      data = JSON.parse(message)
      return unless data.is_a?(Hash)

      # Broadcast via ActionCable to all connected clients
      ActionCable.server.broadcast("dashboard_updates", data)

      Rails.logger.debug do
        symbol = data["symbol"] || data[:symbol]
        ltp = data["ltp"] || data[:ltp]
        "[MarketHub::LtpPubSubListener] 📤 Broadcasted LTP via ActionCable: #{symbol} = ₹#{ltp}"
      end
    rescue JSON::ParserError => e
      Rails.logger.warn("[MarketHub::LtpPubSubListener] Invalid JSON message: #{e.message}")
      Rails.logger.debug("Message: #{message.inspect}")
    end

    def redis_available?
      return false unless defined?(Redis)

      begin
        redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
        test_client = Redis.new(url: redis_url)
        test_client.ping
        test_client.quit
        true
      rescue StandardError => e
        Rails.logger.warn("[MarketHub::LtpPubSubListener] Redis not available: #{e.message}")
        false
      end
    end
  end
end
