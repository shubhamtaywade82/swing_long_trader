# frozen_string_literal: true

module MarketData
  # Standalone WebSocket service that streams LTPs from DhanHQ to Redis
  # This service runs in a separate process (via rake task) and maintains
  # a persistent WebSocket connection, caching LTPs in Redis for fast API reads
  class StreamingService
    require "dhan_hq" unless defined?(DhanHQ)

    LTP_CACHE_TTL = 30.seconds # LTP expires after 30 seconds if not updated
    SUBSCRIPTION_REFRESH_INTERVAL = 5.minutes # Refresh subscription list every 5 minutes
    HEARTBEAT_INTERVAL = 30.seconds # Send heartbeat every 30 seconds

    def initialize(instruments = [])
      # Instruments format: [{segment: 'NSE_EQ', security_id: '1333'}, ...]
      @instruments = instruments
      @client = nil
      @running = false
      @subscriptions = []
      @last_subscription_refresh = Time.current
    end

    def start
      @running = true
      Rails.logger.info("[MarketData::StreamingService] Starting streaming service with #{@instruments.size} instruments")

      unless websocket_enabled?
        Rails.logger.warn("[MarketData::StreamingService] WebSocket not enabled. Set DHANHQ_WS_ENABLED=true")
        return { success: false, error: "WebSocket not enabled" }
      end

      # Load initial instruments if not provided
      refresh_instruments if @instruments.empty?

      # Start WebSocket connection
      connect_and_subscribe

      # Main loop: keep connection alive and refresh subscriptions periodically
      keep_alive_loop

      { success: true }
    rescue StandardError => e
      Rails.logger.error("[MarketData::StreamingService] Error: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      { success: false, error: e.message }
    end

    def stop
      Rails.logger.info("[MarketData::StreamingService] Stopping streaming service")
      @running = false
      unsubscribe_all
      close_websocket_connection
      { success: true, message: "Streaming service stopped" }
    rescue StandardError => e
      Rails.logger.warn("[MarketData::StreamingService] Error during stop: #{e.message}")
      { success: false, error: e.message }
    end

    def update_subscription(new_instruments)
      Rails.logger.info("[MarketData::StreamingService] Updating subscription: #{new_instruments.size} instruments")
      unsubscribe_all
      @instruments = new_instruments
      subscribe_to_instruments(@instruments)
    end

    private

    def websocket_enabled?
      Rails.application.config.x.dhanhq&.ws_enabled == true ||
        ENV["DHANHQ_WS_ENABLED"] == "true"
    end

    def refresh_instruments
      # Fetch active instruments from latest screener results
      Rails.logger.info("[MarketData::StreamingService] Refreshing instrument list from screener results")

      latest_results = ScreenerResult.latest_for(screener_type: "swing", limit: 200)
      instrument_ids = latest_results.pluck(:instrument_id).compact.uniq

      instruments = Instrument.where(id: instrument_ids).includes(:screener_results)
      @instruments = instruments.map do |instrument|
        {
          segment: instrument.exchange_segment,
          security_id: instrument.security_id.to_s,
        }
      end

      Rails.logger.info("[MarketData::StreamingService] Loaded #{@instruments.size} instruments from screener")
    end

    def connect_and_subscribe
      return if @instruments.empty?

      Rails.logger.info("[MarketData::StreamingService] Connecting to DhanHQ WebSocket")

      # Initialize WebSocket client
      mode = ENV.fetch("DHANHQ_WS_MODE", "quote").to_sym
      mode = :quote unless %i[ticker quote full].include?(mode)

      @client = DhanHQ::WS::Client.new(mode: mode).start

      Rails.logger.info("[MarketData::StreamingService] WebSocket client started (mode: #{mode})")

      # Set up tick handler
      @client.on(:tick) do |tick|
        handle_tick(tick)
      end

      # Subscribe to all instruments
      subscribe_to_instruments(@instruments)

      Rails.logger.info("[MarketData::StreamingService] WebSocket connection established with #{@subscriptions.size} subscriptions")
    end

    def subscribe_to_instruments(instruments)
      subscribed_count = 0
      instruments.each do |instrument|
        segment = instrument[:segment] || instrument["segment"]
        security_id = instrument[:security_id] || instrument["security_id"]

        next unless segment && security_id

        begin
          @client.subscribe_one(
            segment: segment,
            security_id: security_id,
          )
          @subscriptions << { segment: segment, security_id: security_id }
          subscribed_count += 1
        rescue StandardError => e
          Rails.logger.warn("[MarketData::StreamingService] Failed to subscribe to #{segment}:#{security_id}: #{e.message}")
        end
      end

      Rails.logger.info("[MarketData::StreamingService] Subscribed to #{subscribed_count}/#{instruments.size} instruments")
    end

    def handle_tick(tick_data)
      return unless tick_data.is_a?(Hash)

      segment = tick_data[:segment] || tick_data["segment"]
      security_id = tick_data[:security_id] || tick_data["security_id"]
      ltp = tick_data[:ltp] || tick_data["ltp"]

      return unless segment && security_id && ltp && ltp.to_f.positive?

      # Cache LTP in Redis with key format: ltp:SEGMENT:SECURITY_ID
      cache_key = "ltp:#{segment}:#{security_id}"
      redis_client.setex(cache_key, LTP_CACHE_TTL.to_i, ltp.to_f.to_s)

      Rails.logger.debug("[MarketData::StreamingService] Cached LTP: #{cache_key} = #{ltp.to_f}")
    rescue StandardError => e
      Rails.logger.error("[MarketData::StreamingService] Error handling tick: #{e.message}")
    end

    def keep_alive_loop
      last_heartbeat = Time.current
      while @running && market_open?
        sleep(5) # Check every 5 seconds

        # Refresh subscriptions periodically
        if Time.current - @last_subscription_refresh >= SUBSCRIPTION_REFRESH_INTERVAL
          refresh_instruments
          update_subscription(@instruments)
          @last_subscription_refresh = Time.current
        end

        # Send heartbeat (update Redis cache to indicate service is alive)
        if Time.current - last_heartbeat >= HEARTBEAT_INTERVAL
          redis_client.setex("market_stream:heartbeat", 60, Time.current.to_i)
          last_heartbeat = Time.current
        end
      end

      Rails.logger.info("[MarketData::StreamingService] Market closed or service stopped, exiting keep_alive_loop")
    end

    def unsubscribe_all
      return unless @client && @subscriptions.any?

      @subscriptions.each do |sub|
        begin
          @client.unsubscribe_one(
            segment: sub[:segment],
            security_id: sub[:security_id],
          )
        rescue StandardError => e
          Rails.logger.warn("[MarketData::StreamingService] Error unsubscribing: #{e.message}")
        end
      end

      @subscriptions.clear
    end

    def close_websocket_connection
      return unless @client

      begin
        if @client.respond_to?(:disconnect!)
          @client.disconnect!
        elsif @client.respond_to?(:stop)
          @client.stop
        end
      rescue StandardError => e
        Rails.logger.warn("[MarketData::StreamingService] Error closing connection: #{e.message}")
      ensure
        @client = nil
      end
    end

    def market_open?
      now = Time.current.in_time_zone("Asia/Kolkata")
      return false unless now.wday.between?(1, 5)

      market_open = now.change(hour: 9, min: 15, sec: 0)
      market_close = now.change(hour: 15, min: 30, sec: 0)

      now >= market_open && now <= market_close
    end

    def redis_client
      @redis_client ||= begin
        # Try to use Redis directly if available, otherwise fall back to Rails.cache
        if defined?(Redis) && ENV["REDIS_URL"].present?
          Redis.new(url: ENV["REDIS_URL"])
        elsif Rails.cache.respond_to?(:redis)
          Rails.cache.redis
        else
          # Fallback: use Rails.cache with manual key management
          # Note: Rails.cache doesn't support MGET directly, so we'll need a workaround
          Rails.cache
        end
      end
    end
  end
end
