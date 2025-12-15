# frozen_string_literal: true

module MarketHub
  # Service to stream live ticks via DhanHQ WebSocket and broadcast to ActionCable
  # This provides true real-time tick updates (not polling-based)
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

      # Initialize DhanHQ WebSocket client for market feed
      @websocket_client = DhanHQ::WebSocket::MarketFeed.new(
        on_tick: method(:handle_tick),
        on_error: method(:handle_error),
        on_close: method(:handle_close),
      )

      # Subscribe to all instruments
      @websocket_client.subscribe(@subscriptions)

      Rails.logger.info("[MarketHub::WebsocketTickStreamer] Subscribed to #{@subscriptions.size} instruments")
    end

    def handle_tick(tick_data)
      # tick_data format: { ExchangeSegment, SecurityId, LastPrice, ... }
      symbol = find_symbol_for_tick(tick_data)
      return unless symbol

      # Broadcast immediately via ActionCable
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_ltp_update",
          symbol: symbol,
          instrument_id: find_instrument_id_for_tick(tick_data),
          ltp: tick_data["LastPrice"] || tick_data[:LastPrice] || tick_data["last_price"],
          timestamp: Time.current.iso8601,
          source: "websocket", # Indicate this is real-time, not polled
        },
      )
    rescue StandardError => e
      Rails.logger.error("[MarketHub::WebsocketTickStreamer] Error handling tick: #{e.message}")
    end

    def handle_error(error)
      Rails.logger.error("[MarketHub::WebsocketTickStreamer] WebSocket error: #{error.message}")
      # Attempt reconnection
      reconnect_websocket
    end

    def handle_close
      Rails.logger.warn("[MarketHub::WebsocketTickStreamer] WebSocket connection closed")
      # Attempt reconnection if market is still open
      reconnect_websocket if market_open?
    end

    def reconnect_websocket
      return unless market_open?

      Rails.logger.info("[MarketHub::WebsocketTickStreamer] Attempting reconnection...")
      sleep(2) # Wait before reconnecting
      start_websocket_connection
    end

    def unsubscribe_all
      @websocket_client&.unsubscribe(@subscriptions) if @websocket_client
      @subscriptions.clear
    end

    def close_websocket_connection
      @websocket_client&.close if @websocket_client
      @websocket_client = nil
    end

    def find_symbol_for_tick(tick_data)
      exchange_segment = tick_data["ExchangeSegment"] || tick_data[:ExchangeSegment]
      security_id = tick_data["SecurityId"] || tick_data[:SecurityId]

      return nil unless exchange_segment && security_id

      instrument = Instrument.find_by(
        exchange_segment: exchange_segment,
        security_id: security_id.to_s,
      )
      instrument&.symbol_name
    end

    def find_instrument_id_for_tick(tick_data)
      exchange_segment = tick_data["ExchangeSegment"] || tick_data[:ExchangeSegment]
      security_id = tick_data["SecurityId"] || tick_data[:SecurityId]

      return nil unless exchange_segment && security_id

      instrument = Instrument.find_by(
        exchange_segment: exchange_segment,
        security_id: security_id.to_s,
      )
      instrument&.id
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
