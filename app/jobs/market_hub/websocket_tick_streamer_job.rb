# frozen_string_literal: true

module MarketHub
  # Background job to maintain WebSocket connection for real-time tick streaming
  # This provides true real-time updates (not polling-based)
  #
  # Architecture:
  # - Runs WebSocket connection in a separate thread to avoid blocking job thread
  # - Job completes immediately, thread continues running until market closes
  # - Thread is automatically cleaned up when market closes or on error
  # - Uses Rails.cache for cross-process thread tracking
  class WebsocketTickStreamerJob < ApplicationJob
    queue_as :monitoring

    # Thread tracking: in-process threads (for quick access)
    @@active_threads = Concurrent::Map.new

    # Cache keys for cross-process tracking
    STREAM_KEY_PREFIX = "websocket_stream"
    STREAM_TTL = 1.hour # Stream should refresh every hour if healthy

    def perform(screener_type: nil, instrument_ids: nil, symbols: nil)
      return unless market_open?

      # Convert instrument_ids string to array if needed
      instrument_ids = instrument_ids.split(",").map(&:to_i) if instrument_ids.is_a?(String)
      symbols = symbols.split(",") if symbols.is_a?(String)

      # Create unique key for this stream
      stream_key = stream_key(screener_type, instrument_ids, symbols)
      cache_key = "#{STREAM_KEY_PREFIX}:#{stream_key}"

      # Check if stream is already running (cross-process check using cache)
      if stream_running?(stream_key, cache_key)
        Rails.logger.info(
          "[MarketHub::WebsocketTickStreamerJob] WebSocket stream already running for key: #{stream_key}",
        )
        return
      end

      # Mark stream as starting (with short TTL to prevent race conditions)
      mark_stream_starting(cache_key)

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

            # Mark stream as running (cross-process)
            mark_stream_running(stream_key, cache_key)

            # Keep thread alive while market is open
            # EventMachine event loop runs in this thread
            # Refresh cache every 30 seconds to indicate stream is alive
            last_refresh = Time.current
            while market_open?
              sleep(5) # Check every 5 seconds if market is still open

              # Refresh cache every 30 seconds to indicate stream is alive
              if Time.current - last_refresh >= 30
                refresh_stream_heartbeat(cache_key)
                last_refresh = Time.current
              end
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
          mark_stream_stopped(stream_key, cache_key)
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
      thread_count = @@active_threads.size
      Rails.logger.info(
        "[MarketHub::WebsocketTickStreamerJob] Stopping all active WebSocket streams (#{thread_count} threads, #{active_stream_count} alive)",
      )
      @@active_threads.each do |key, thread|
        next unless thread.alive?

        Rails.logger.info("[MarketHub::WebsocketTickStreamerJob] Stopping stream: #{key}")
        begin
          # Try graceful stop first
          thread.raise(Interrupt) # Signal thread to stop
          sleep(1) # Give thread time to cleanup
          thread.kill unless thread.alive? # Force kill if still alive
        rescue StandardError => e
          Rails.logger.warn("[MarketHub::WebsocketTickStreamerJob] Error stopping thread #{key}: #{e.message}")
          thread.kill # Force kill on error
        end

        # Clean up cache
        cache_key = "#{STREAM_KEY_PREFIX}:#{key}"
        Rails.cache.delete(cache_key)
      end
      @@active_threads.clear
    end

    # Class method to get active stream count (in-process threads)
    def self.active_stream_count
      count = 0
      @@active_threads.each { |_key, thread| count += 1 if thread.alive? }
      count
    end

    # Class method to get all active streams across all processes (using cache)
    def self.active_streams_count_cross_process
      # This is approximate - counts cache entries with stream keys
      # In production, you might want a more sophisticated tracking mechanism
      count = 0
      @@active_threads.each_key do |key|
        cache_key = "#{STREAM_KEY_PREFIX}:#{key}"
        count += 1 if Rails.cache.exist?(cache_key)
      end
      count
    end

    # Class method to cleanup stale streams (should be called periodically)
    def self.cleanup_stale_streams
      cleaned = 0
      @@active_threads.each do |key, thread|
        cache_key = "#{STREAM_KEY_PREFIX}:#{key}"
        # If thread is dead but cache still exists, clean it up
        next if thread.alive?

        Rails.cache.delete(cache_key)
        @@active_threads.delete(key)
        cleaned += 1
      end
      Rails.logger.info("[MarketHub::WebsocketTickStreamerJob] Cleaned up #{cleaned} stale streams") if cleaned > 0
      cleaned
    end

    # Class method to get stream status
    def self.stream_status(stream_key)
      cache_key = "#{STREAM_KEY_PREFIX}:#{stream_key}"
      thread = @@active_threads[stream_key]
      cache_data = Rails.cache.read(cache_key)

      {
        thread_alive: thread&.alive? || false,
        cache_exists: cache_data.present?,
        cache_data: cache_data,
        process_id: Process.pid,
      }
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

    # Check if stream is running (cross-process check)
    def stream_running?(stream_key, cache_key)
      # First check in-process thread
      return true if @@active_threads.key?(stream_key) && @@active_threads[stream_key].alive?

      # Then check cache (cross-process)
      cache_data = Rails.cache.read(cache_key)
      return false unless cache_data

      # Check if cache indicates stream is running
      status = begin
        cache_data[:status]
      rescue StandardError
        nil
      end
      return false unless status == "running"

      # Check if heartbeat is recent (within last 2 minutes)
      heartbeat = begin
        cache_data[:heartbeat]
      rescue StandardError
        nil
      end
      return false unless heartbeat

      heartbeat_time = begin
        Time.parse(heartbeat)
      rescue StandardError
        nil
      end
      return false unless heartbeat_time

      Time.current - heartbeat_time < 2.minutes
    end

    # Mark stream as starting (short TTL to prevent race conditions)
    def mark_stream_starting(cache_key)
      Rails.cache.write(
        cache_key,
        {
          status: "starting",
          process_id: Process.pid,
          started_at: Time.current.iso8601,
          heartbeat: Time.current.iso8601,
        },
        expires_in: 1.minute,
      )
    end

    # Mark stream as running
    def mark_stream_running(stream_key, cache_key)
      Rails.cache.write(
        cache_key,
        {
          status: "running",
          stream_key: stream_key,
          process_id: Process.pid,
          started_at: Time.current.iso8601,
          heartbeat: Time.current.iso8601,
        },
        expires_in: STREAM_TTL,
      )
    end

    # Refresh stream heartbeat
    def refresh_stream_heartbeat(cache_key)
      cache_data = Rails.cache.read(cache_key)
      return unless cache_data

      cache_data[:heartbeat] = Time.current.iso8601
      Rails.cache.write(cache_key, cache_data, expires_in: STREAM_TTL)
    end

    # Mark stream as stopped
    def mark_stream_stopped(stream_key, cache_key)
      Rails.cache.delete(cache_key)
    end
  end
end
