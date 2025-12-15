# frozen_string_literal: true

module MarketHub
  # Background job to maintain WebSocket connection for real-time tick streaming
  # This provides true real-time updates (not polling-based)
  #
  # Architecture:
  # - Runs WebSocket connection in a separate thread to avoid blocking job thread
  # - Job completes immediately, thread continues running until market closes
  # - Thread is automatically cleaned up when market closes or on error
  class WebsocketTickStreamerJob < ApplicationJob
    queue_as :monitoring

    # Store active WebSocket threads to allow cleanup if needed
    @@active_threads = Concurrent::Map.new

    def perform(screener_type: nil, instrument_ids: nil, symbols: nil)
      return unless market_open?

      # Convert instrument_ids string to array if needed
      instrument_ids = instrument_ids.split(",").map(&:to_i) if instrument_ids.is_a?(String)
      symbols = symbols.split(",") if symbols.is_a?(String)

      # Create unique key for this stream
      stream_key = stream_key(screener_type, instrument_ids, symbols)

      # Check if stream is already running (within same process)
      # Note: For multi-process environments, controller-level checks prevent duplicate enqueueing
      if @@active_threads.key?(stream_key) && @@active_threads[stream_key].alive?
        Rails.logger.info(
          "[MarketHub::WebsocketTickStreamerJob] WebSocket stream already running for key: #{stream_key}",
        )
        return
      end

      # Run WebSocket connection in a separate thread to avoid blocking job thread
      websocket_thread = Thread.new do
        Thread.current.name = "WebSocketStreamer-#{stream_key}"
        Thread.current.abort_on_exception = false # Handle errors gracefully

        begin
          Rails.logger.info(
            "[MarketHub::WebsocketTickStreamerJob] Starting WebSocket thread for key: #{stream_key}",
          )

          # Initialize WebSocket streamer
          streamer = MarketHub::WebsocketTickStreamer.new(
            instrument_ids: instrument_ids,
            symbols: symbols,
          )

          # Start WebSocket connection
          result = streamer.call

          if result[:success]
            Rails.logger.info(
              "[MarketHub::WebsocketTickStreamerJob] WebSocket started: #{result[:subscribed_count]} instruments subscribed",
            )

            # Keep thread alive while market is open
            # EventMachine event loop runs in this thread
            while market_open?
              sleep(5) # Check every 5 seconds if market is still open
            end

            Rails.logger.info(
              "[MarketHub::WebsocketTickStreamerJob] Market closed, stopping WebSocket stream",
            )
          else
            Rails.logger.error(
              "[MarketHub::WebsocketTickStreamerJob] Failed to start WebSocket: #{result[:error]}",
            )
            # Retry if market is still open
            if market_open?
              sleep(10)
              MarketHub::WebsocketTickStreamerJob.perform_later(
                screener_type: screener_type,
                instrument_ids: instrument_ids&.join(","),
                symbols: symbols&.join(","),
              )
            end
          end
        rescue StandardError => e
          Rails.logger.error(
            "[MarketHub::WebsocketTickStreamerJob] WebSocket thread error: #{e.message}",
          )
          Rails.logger.error(e.backtrace.first(10).join("\n"))

          # Retry if market is still open
          if market_open?
            sleep(10)
            MarketHub::WebsocketTickStreamerJob.perform_later(
              screener_type: screener_type,
              instrument_ids: instrument_ids&.join(","),
              symbols: symbols&.join(","),
            )
          end
        ensure
          # Cleanup: stop streamer and remove from active threads
          begin
            streamer&.stop
          rescue StandardError => e
            Rails.logger.warn(
              "[MarketHub::WebsocketTickStreamerJob] Error stopping streamer: #{e.message}",
            )
          end

          @@active_threads.delete(stream_key)
          Rails.logger.info(
            "[MarketHub::WebsocketTickStreamerJob] WebSocket thread cleaned up for key: #{stream_key}",
          )
        end
      end

      # Store thread reference for potential cleanup
      @@active_threads[stream_key] = websocket_thread

      # Job completes immediately, thread continues running
      Rails.logger.info(
        "[MarketHub::WebsocketTickStreamerJob] Job completed, WebSocket running in thread: #{websocket_thread.name}",
      )
    rescue StandardError => e
      Rails.logger.error("[MarketHub::WebsocketTickStreamerJob] Job error: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
    end

    # Class method to stop all active WebSocket streams (useful for graceful shutdown)
    def self.stop_all_streams
      Rails.logger.info(
        "[MarketHub::WebsocketTickStreamerJob] Stopping all active WebSocket streams (#{@@active_threads.size} active)",
      )
      @@active_threads.each do |key, thread|
        next unless thread.alive?

        Rails.logger.info("[MarketHub::WebsocketTickStreamerJob] Stopping stream: #{key}")
        thread.kill # Force stop thread
      end
      @@active_threads.clear
    end

    # Class method to get active stream count
    def self.active_stream_count
      @@active_threads.count { |_key, thread| thread.alive? }
    end

    private

    def stream_key(screener_type, instrument_ids, symbols)
      parts = []
      parts << "type:#{screener_type}" if screener_type
      parts << "ids:#{instrument_ids&.join(',')}" if instrument_ids&.any?
      parts << "symbols:#{symbols&.join(',')}" if symbols&.any?
      parts.any? ? parts.join("|") : "default"
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
