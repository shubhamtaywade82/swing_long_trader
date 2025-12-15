# frozen_string_literal: true

module MarketHub
  # Service to stream live ticks via DhanHQ WebSocket and broadcast to ActionCable
  # This provides true real-time tick updates (not polling-based)
  # Based on dhanhq-client gem: https://github.com/shubhamtaywade82/dhanhq-client
  class WebsocketTickStreamer < ApplicationService
    require "dhan_hq" unless defined?(DhanHQ)

    def initialize(instrument_ids: [], symbols: [])
      @instrument_ids = Array(instrument_ids)
      @symbols = Array(symbols)
      @subscriptions = []
      @websocket_client = nil
    end

    def call
      Rails.logger.info(
        "[MarketHub::WebsocketTickStreamer] Starting WebSocket streamer (instrument_ids: #{@instrument_ids.size}, symbols: #{@symbols.size})",
      )

      unless websocket_enabled?
        Rails.logger.warn(
          "[MarketHub::WebsocketTickStreamer] WebSocket not enabled. Set DHANHQ_WS_ENABLED=true or config.x.dhanhq.ws_enabled=true",
        )
        return { success: false, error: "WebSocket not enabled" }
      end

      instruments = fetch_instruments
      if instruments.empty?
        Rails.logger.warn(
          "[MarketHub::WebsocketTickStreamer] No instruments found to subscribe to",
        )
        return { success: false, error: "No instruments found" }
      end

      Rails.logger.info(
        "[MarketHub::WebsocketTickStreamer] Found #{instruments.size} instruments to subscribe",
      )

      subscribe_to_ticks(instruments)
      result = start_websocket_connection

      # If start_websocket_connection returned an error, return it
      return result if result.is_a?(Hash) && result[:success] == false

      Rails.logger.info(
        "[MarketHub::WebsocketTickStreamer] Successfully started WebSocket streamer with #{@subscriptions.size} subscriptions",
      )

      {
        success: true,
        subscribed_count: @subscriptions.size,
        timestamp: Time.current,
      }
    rescue StandardError => e
      Rails.logger.error("[MarketHub::WebsocketTickStreamer] Error: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      { success: false, error: e.message }
    end

    def stop
      unsubscribe_all
      close_websocket_connection
      { success: true, message: "WebSocket stream stopped" }
    rescue StandardError => e
      Rails.logger.warn("[MarketHub::WebsocketTickStreamer] Error during stop: #{e.message}")
      { success: false, error: e.message }
    end

    private

    def websocket_enabled?
      Rails.application.config.x.dhanhq&.ws_enabled == true ||
        ENV["DHANHQ_WS_ENABLED"] == "true"
    end

    def fetch_instruments
      instruments = if @instrument_ids.any?
                      Instrument.where(id: @instrument_ids)
                    elsif @symbols.any?
                      Instrument.where(symbol_name: @symbols)
                    else
                      # Default: get latest screener results
                      latest_results = ScreenerResult.latest_for(screener_type: "swing", limit: 200)
                      instrument_ids = latest_results.pluck(:instrument_id).compact.uniq
                      Instrument.where(id: instrument_ids)
                    end

      Rails.logger.info(
        "[MarketHub::WebsocketTickStreamer] Fetching instruments: requested #{@instrument_ids.size} IDs, #{@symbols.size} symbols, found #{instruments.count} instruments",
      )
      if instruments.any?
        Rails.logger.debug { "[MarketHub::WebsocketTickStreamer] Instrument IDs: #{instruments.pluck(:id).first(10).inspect}" }
      end

      instruments
    end

    def subscribe_to_ticks(instruments)
      # Format subscription params for dhanhq-client gem API
      # API: ws.subscribe_one(segment: "NSE_EQ", security_id: "12345")
      # Note: Up to 100 instruments per SUB message (client auto-chunks)
      instruments.each do |instrument|
        subscription_params = {
          ExchangeSegment: instrument.exchange_segment,
          SecurityId: instrument.security_id.to_s,
        }
        @subscriptions << subscription_params
      end
    end

    def start_websocket_connection
      return unless @subscriptions.any?

      begin
        # Initialize WebSocket client using dhanhq-client gem API
        # API: DhanHQ::WS::Client.new(mode: :quote).start
        # Modes: :ticker (LTP+LTT), :quote (OHLCV+totals, recommended), :full (quote+OI+depth)
        mode = ENV.fetch("DHANHQ_WS_MODE", "quote").to_sym
        mode = :quote unless %i[ticker quote full].include?(mode)

        Rails.logger.info(
          "[MarketHub::WebsocketTickStreamer] Initializing WebSocket client (mode: #{mode}) for #{@subscriptions.size} instruments",
        )

        @websocket_client = DhanHQ::WS::Client.new(mode: mode).start

        Rails.logger.info(
          "[MarketHub::WebsocketTickStreamer] WebSocket client started successfully",
        )

        # Set up tick handler
        # API: ws.on(:tick) { |t| ... }
        @websocket_client.on(:tick) do |tick|
          handle_tick(tick)
        end

        Rails.logger.info(
          "[MarketHub::WebsocketTickStreamer] Tick handler registered",
        )

        # Subscribe to all instruments
        # API: ws.subscribe_one(segment: "NSE_EQ", security_id: "12345")
        # Note: Up to 100 instruments per message (client auto-chunks)
        subscribed_count = 0
        @subscriptions.each do |sub|
          segment = sub[:ExchangeSegment] || sub["ExchangeSegment"]
          security_id = sub[:SecurityId] || sub["SecurityId"]

          Rails.logger.debug { "[MarketHub::WebsocketTickStreamer] Subscribing to segment: #{segment}, security_id: #{security_id}" }

          @websocket_client.subscribe_one(
            segment: segment,
            security_id: security_id,
          )
          subscribed_count += 1
        end

        Rails.logger.info(
          "[MarketHub::WebsocketTickStreamer] WebSocket connection established and subscribed to #{subscribed_count}/#{@subscriptions.size} instruments (mode: #{mode})",
        )

        # Return success (nil means success, method will return nil by default)
        nil
      rescue NameError => e
        error_msg = "WebSocket API not available in dhanhq-client gem: #{e.message}"
        Rails.logger.error("[MarketHub::WebsocketTickStreamer] #{error_msg}")
        Rails.logger.error("Please ensure dhanhq-client gem is updated: https://github.com/shubhamtaywade82/dhanhq-client")
        Rails.logger.error("Backtrace: #{e.backtrace.first(5).join("\n")}")
        # Return error instead of raising to prevent job crash
        { success: false, error: error_msg }
      rescue LoadError => e
        error_msg = "DhanHQ gem not installed: #{e.message}"
        Rails.logger.error("[MarketHub::WebsocketTickStreamer] #{error_msg}")
        Rails.logger.error("Backtrace: #{e.backtrace.first(5).join("\n")}")
        { success: false, error: error_msg }
      rescue StandardError => e
        error_msg = "Failed to start WebSocket: #{e.message}"
        Rails.logger.error("[MarketHub::WebsocketTickStreamer] #{error_msg}")
        Rails.logger.error("Backtrace: #{e.backtrace.first(10).join("\n")}")
        # Return error instead of raising to prevent job crash
        { success: false, error: error_msg }
      end
    end

    def handle_tick(tick_data)
      # Tick format from dhanhq-client gem (normalized Hash):
      # {
      #   kind: :quote,                 # :ticker | :quote | :full | :oi | :prev_close | :misc
      #   segment: "NSE_FNO",           # string enum
      #   security_id: "12345",
      #   ltp: 101.5,
      #   ts:  1723791300,              # LTT epoch (sec) if present
      #   vol: 123456,                  # quote/full
      #   atp: 100.9,                   # quote/full
      #   day_open: 100.1, day_high: 102.4, day_low: 99.5, day_close: nil,
      #   oi: 987654,                   # full or OI packet
      #   bid: 101.45, ask: 101.55      # from depth (mode :full)
      # }

      # Always log tick reception (not just in development) to verify WebSocket is receiving data
      Rails.logger.info(
        "[MarketHub::WebsocketTickStreamer] 📥 Received tick: segment=#{tick_data[:segment] || tick_data['segment']}, security_id=#{tick_data[:security_id] || tick_data['security_id']}, ltp=#{tick_data[:ltp] || tick_data['ltp']}",
      )

      return unless tick_data.is_a?(Hash)

      segment = tick_data[:segment] || tick_data["segment"]
      security_id = tick_data[:security_id] || tick_data["security_id"]
      ltp = tick_data[:ltp] || tick_data["ltp"]

      unless segment && security_id && ltp && ltp.to_f.positive?
        Rails.logger.warn(
          "[MarketHub::WebsocketTickStreamer] ⚠️ Invalid tick data: segment=#{segment}, security_id=#{security_id}, ltp=#{ltp}",
        )
        return
      end

      # Find instrument and symbol
      instrument = Instrument.find_by(
        exchange_segment: segment,
        security_id: security_id.to_s,
      )

      unless instrument
        Rails.logger.warn(
          "[MarketHub::WebsocketTickStreamer] Instrument not found for segment: #{segment}, security_id: #{security_id}",
        )
        return
      end

      # Cache LTP in Redis for fast API reads (key format: ltp:SEGMENT:SECURITY_ID)
      cache_key = "ltp:#{segment}:#{security_id}"
      redis_client.setex(cache_key, 30, ltp.to_f.to_s)

      # Broadcast immediately via ActionCable
      broadcast_data = {
        type: "screener_ltp_update",
        symbol: instrument.symbol_name,
        instrument_id: instrument.id,
        ltp: ltp.to_f,
        timestamp: Time.current.iso8601,
        source: "websocket", # Indicate this is real-time, not polled
        tick_kind: tick_data[:kind] || tick_data["kind"], # :ticker, :quote, :full, etc.
        volume: tick_data[:vol] || tick_data["vol"],
        day_open: tick_data[:day_open] || tick_data["day_open"],
        day_high: tick_data[:day_high] || tick_data["day_high"],
        day_low: tick_data[:day_low] || tick_data["day_low"],
      }

      ActionCable.server.broadcast("dashboard_updates", broadcast_data)

      # Always log broadcasts (not just in development) to track if messages are being sent
      Rails.logger.debug(
        "[MarketHub::WebsocketTickStreamer] 📡 Cached & broadcasted LTP: #{instrument.symbol_name} (#{instrument.id}) = ₹#{ltp.to_f}",
      )
    rescue StandardError => e
      Rails.logger.error("[MarketHub::WebsocketTickStreamer] Error handling tick: #{e.message}")
      Rails.logger.error("Tick data: #{tick_data.inspect}")
    end

    def handle_error(error)
      Rails.logger.error("[MarketHub::WebsocketTickStreamer] WebSocket error: #{error.message}")
      # NOTE: dhanhq-client gem handles reconnection automatically with exponential backoff
      # On reconnect, the client resends the current subscription snapshot (idempotent)
    end

    def handle_close
      Rails.logger.warn("[MarketHub::WebsocketTickStreamer] WebSocket connection closed")
      # NOTE: dhanhq-client gem handles reconnection automatically
      # Only reconnect manually if needed (e.g., after graceful disconnect)
      return unless market_open? && @websocket_client.nil?

      Rails.logger.info("[MarketHub::WebsocketTickStreamer] Attempting reconnection...")
      sleep(2) # Wait before reconnecting
      start_websocket_connection
    end

    def unsubscribe_all
      return unless @websocket_client

      begin
        # API: ws.unsubscribe_one(segment: "NSE_EQ", security_id: "12345")
        @subscriptions.each do |sub|
          @websocket_client.unsubscribe_one(
            segment: sub[:ExchangeSegment] || sub["ExchangeSegment"],
            security_id: sub[:SecurityId] || sub["SecurityId"],
          )
        end
      rescue StandardError => e
        Rails.logger.warn("[MarketHub::WebsocketTickStreamer] Error unsubscribing: #{e.message}")
      ensure
        @subscriptions.clear
      end
    end

    def close_websocket_connection
      return unless @websocket_client

      begin
        # API: ws.disconnect! (graceful) or ws.stop (hard stop)
        # Use disconnect! for graceful shutdown (sends broker disconnect code 12, no reconnect)
        if @websocket_client.respond_to?(:disconnect!)
          @websocket_client.disconnect!
        elsif @websocket_client.respond_to?(:stop)
          @websocket_client.stop
        end
      rescue StandardError => e
        Rails.logger.warn("[MarketHub::WebsocketTickStreamer] Error closing connection: #{e.message}")
      ensure
        @websocket_client = nil
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
          Rails.cache
        end
      end
    end
  end
end
