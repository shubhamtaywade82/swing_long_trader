# frozen_string_literal: true

module MarketHub
  # Periodic job to cleanup stale WebSocket streams and monitor health
  # Should run every 5 minutes during market hours
  class WebsocketHealthCheckJob < ApplicationJob
    queue_as :monitoring

    def perform
      return unless market_open?

      # Cleanup stale threads
      cleaned = MarketHub::WebsocketTickStreamerJob.cleanup_stale_streams

      # Log health status
      active_count = MarketHub::WebsocketTickStreamerJob.active_stream_count
      cross_process_count = MarketHub::WebsocketTickStreamerJob.active_streams_count_cross_process

      Rails.logger.info(
        "[MarketHub::WebsocketHealthCheckJob] Health check: " \
        "#{active_count} active threads (this process), " \
        "#{cross_process_count} streams (cross-process), " \
        "#{cleaned} stale streams cleaned",
      )

      # Schedule next health check
      MarketHub::WebsocketHealthCheckJob.set(wait: 5.minutes).perform_later if market_open?
    rescue StandardError => e
      Rails.logger.error("[MarketHub::WebsocketHealthCheckJob] Error: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
    end

    private

    def market_open?
      now = Time.current.in_time_zone("Asia/Kolkata")
      return false unless now.wday.between?(1, 5)

      market_open = now.change(hour: 9, min: 15, sec: 0)
      market_close = now.change(hour: 15, min: 30, sec: 0)

      now >= market_open && now <= market_close
    end
  end
end
