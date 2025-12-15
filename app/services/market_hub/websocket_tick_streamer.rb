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
      return { success: false, error: "WebSocket not enabled" } unless websocket_enabled?

      instruments = fetch_instruments
      return { success: false, error: "No instruments found" } if instruments.empty?

      subscribe_to_ticks(instruments)
      start_websocket_connection

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
      if @instrument_ids.any?
        Instrument.where(id: @instrument_ids)
      elsif @symbols.any?
        Instrument.where(symbol_name: @symbols)
      else
        # Default: get latest screener results
        latest_results = ScreenerResult.latest_for(screener_type: "swing", limit: 200)
        instrument_ids = latest_results.pluck(:instrument_id).compact.uniq
        Instrument.where(id: instrument_ids)
      end
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

        @websocket_client = DhanHQ::WS::Client.new(mode: mode).start

        # Set up tick handler
        # API: ws.on(:tick) { |t| ... }
        @websocket_client.on(:tick) do |tick|
          handle_tick(tick)
        end

        # Subscribe to all instruments
        # API: ws.subscribe_one(segment: "NSE_EQ", security_id: "12345")
        # Note: Up to 100 instruments per message (client auto-chunks)
        @subscriptions.each do |sub|
          @websocket_client.subscribe_one(
            segment: sub[:ExchangeSegment] || sub["ExchangeSegment"],
            security_id: sub[:SecurityId] || sub["SecurityId"],
          )
        end

        Rails.logger.info(
          "[MarketHub::WebsocketTickStreamer] Started WebSocket (mode: #{mode}) and subscribed to #{@subscriptions.size} instruments",
        )
      rescue NameError => e
        Rails.logger.error("[MarketHub::WebsocketTickStreamer] WebSocket API not available: #{e.message}")
        Rails.logger.error("Please ensure dhanhq-client gem is updated: https://github.com/shubhamtaywade82/dhanhq-client")
        raise StandardError, "WebSocket not available in dhanhq-client gem. Error: #{e.message}"
      rescue StandardError => e
        Rails.logger.error("[MarketHub::WebsocketTickStreamer] Failed to start WebSocket: #{e.message}")
        raise
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
      
      return unless tick_data.is_a?(Hash)

      segment = tick_data[:segment] || tick_data["segment"]
      security_id = tick_data[:security_id] || tick_data["security_id"]
      ltp = tick_data[:ltp] || tick_data["ltp"]

      return unless segment && security_id && ltp && ltp.to_f.positive?

      # Find instrument and symbol
      instrument = Instrument.find_by(
        exchange_segment: segment,
        security_id: security_id.to_s,
      )
      return unless instrument

      # Broadcast immediately via ActionCable
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
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
        },
      )
    rescue StandardError => e
      Rails.logger.error("[MarketHub::WebsocketTickStreamer] Error handling tick: #{e.message}")
      Rails.logger.error("Tick data: #{tick_data.inspect}")
    end

    def handle_error(error)
      Rails.logger.error("[MarketHub::WebsocketTickStreamer] WebSocket error: #{error.message}")
      # Note: dhanhq-client gem handles reconnection automatically with exponential backoff
      # On reconnect, the client resends the current subscription snapshot (idempotent)
    end

    def handle_close
      Rails.logger.warn("[MarketHub::WebsocketTickStreamer] WebSocket connection closed")
      # Note: dhanhq-client gem handles reconnection automatically
      # Only reconnect manually if needed (e.g., after graceful disconnect)
      if market_open? && @websocket_client.nil?
        Rails.logger.info("[MarketHub::WebsocketTickStreamer] Attempting reconnection...")
        sleep(2) # Wait before reconnecting
        start_websocket_connection
      end
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
  end
end
