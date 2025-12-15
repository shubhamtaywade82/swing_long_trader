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
        # Format subscription params according to dhanhq-client gem API
        subscription_params = {
          ExchangeSegment: instrument.exchange_segment,
          SecurityId: instrument.security_id.to_s,
        }
        @subscriptions << subscription_params
      end
    end

    def start_websocket_connection
      return unless @subscriptions.any?

      # Try different possible WebSocket API structures from dhanhq-client gem
      # The gem may expose WebSocket via:
      # 1. DhanHQ::WebSocket::MarketFeed
      # 2. DhanHQ::Client with websocket option
      # 3. DhanHQ::WebSocket::Client
      # 4. DhanHQ::MarketFeed::WebSocket

      begin
        # Try the most likely API structure based on gem patterns
        if defined?(DhanHQ::WebSocket) && DhanHQ::WebSocket.const_defined?(:MarketFeed)
          # Option 1: DhanHQ::WebSocket::MarketFeed
          @websocket_client = DhanHQ::WebSocket::MarketFeed.new(
            on_tick: method(:handle_tick),
            on_error: method(:handle_error),
            on_close: method(:handle_close),
          )
        elsif defined?(DhanHQ::WebSocket) && DhanHQ::WebSocket.const_defined?(:Client)
          # Option 2: DhanHQ::WebSocket::Client
          @websocket_client = DhanHQ::WebSocket::Client.new(
            type: :market_feed,
            on_tick: method(:handle_tick),
            on_error: method(:handle_error),
            on_close: method(:handle_close),
          )
        elsif DhanHQ::Client.instance_methods.include?(:websocket) || DhanHQ::Client.instance_methods.include?(:market_feed_websocket)
          # Option 3: DhanHQ::Client with websocket method
          client = DhanHQ::Client.new(api_type: :data_api)
          @websocket_client = client.market_feed_websocket(
            on_tick: method(:handle_tick),
            on_error: method(:handle_error),
            on_close: method(:handle_close),
          )
        else
          # Fallback: Try to instantiate directly and let gem handle it
          # This will raise an error if WebSocket is not available, which we'll catch
          raise NotImplementedError, "WebSocket API not found in dhanhq-client gem"
        end

        # Subscribe to all instruments
        # The gem's subscribe method may accept:
        # - Array of subscription params
        # - Single subscription param
        # - Hash with :subscriptions key
        if @websocket_client.respond_to?(:subscribe)
          if @subscriptions.size == 1
            @websocket_client.subscribe(@subscriptions.first)
          else
            @websocket_client.subscribe(@subscriptions)
          end
        elsif @websocket_client.respond_to?(:add_subscription)
          @subscriptions.each { |sub| @websocket_client.add_subscription(sub) }
        else
          raise NotImplementedError, "Subscribe method not found on WebSocket client"
        end

        Rails.logger.info("[MarketHub::WebsocketTickStreamer] Subscribed to #{@subscriptions.size} instruments")
      rescue NameError, NotImplementedError => e
        Rails.logger.error("[MarketHub::WebsocketTickStreamer] WebSocket API not available: #{e.message}")
        Rails.logger.error("Please check dhanhq-client gem documentation: https://github.com/shubhamtaywade82/dhanhq-client")
        raise StandardError, "WebSocket not available in dhanhq-client gem. Error: #{e.message}"
      end
    end

    def handle_tick(tick_data)
      # tick_data format varies by gem version, handle multiple formats:
      # - Hash with string keys: { "ExchangeSegment" => "...", "SecurityId" => "...", "LastPrice" => ... }
      # - Hash with symbol keys: { ExchangeSegment: "...", SecurityId: "...", LastPrice: ... }
      # - Object with methods: tick_data.ExchangeSegment, tick_data.SecurityId, tick_data.LastPrice
      
      tick_hash = if tick_data.is_a?(Hash)
                    tick_data
                  elsif tick_data.respond_to?(:to_h)
                    tick_data.to_h
                  else
                    # Try to convert object to hash
                    tick_data.instance_variables.each_with_object({}) do |var, hash|
                      key = var.to_s.delete("@").to_sym
                      hash[key] = tick_data.instance_variable_get(var)
                    end
                  end

      symbol = find_symbol_for_tick(tick_hash)
      return unless symbol

      # Extract LTP from various possible field names
      ltp = tick_hash["LastPrice"] || 
            tick_hash[:LastPrice] || 
            tick_hash["last_price"] || 
            tick_hash[:last_price] ||
            tick_hash["LTP"] ||
            tick_hash[:ltp] ||
            (tick_data.respond_to?(:last_price) ? tick_data.last_price : nil) ||
            (tick_data.respond_to?(:LastPrice) ? tick_data.LastPrice : nil)

      return unless ltp && ltp.to_f.positive?

      # Broadcast immediately via ActionCable
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_ltp_update",
          symbol: symbol,
          instrument_id: find_instrument_id_for_tick(tick_hash),
          ltp: ltp.to_f,
          timestamp: Time.current.iso8601,
          source: "websocket", # Indicate this is real-time, not polled
        },
      )
    rescue StandardError => e
      Rails.logger.error("[MarketHub::WebsocketTickStreamer] Error handling tick: #{e.message}")
      Rails.logger.error("Tick data: #{tick_data.inspect}")
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
      return unless @websocket_client

      begin
        if @websocket_client.respond_to?(:unsubscribe)
          if @subscriptions.size == 1
            @websocket_client.unsubscribe(@subscriptions.first)
          else
            @websocket_client.unsubscribe(@subscriptions)
          end
        elsif @websocket_client.respond_to?(:remove_subscription)
          @subscriptions.each { |sub| @websocket_client.remove_subscription(sub) }
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
        if @websocket_client.respond_to?(:close)
          @websocket_client.close
        elsif @websocket_client.respond_to?(:disconnect)
          @websocket_client.disconnect
        end
      rescue StandardError => e
        Rails.logger.warn("[MarketHub::WebsocketTickStreamer] Error closing connection: #{e.message}")
      ensure
        @websocket_client = nil
      end
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
