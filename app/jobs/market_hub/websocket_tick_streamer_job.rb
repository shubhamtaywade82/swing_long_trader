# frozen_string_literal: true

module MarketHub
  # Background job to maintain WebSocket connection for real-time tick streaming
  # This provides true real-time updates (not polling-based)
  class WebsocketTickStreamerJob < ApplicationJob
    queue_as :monitoring

    def perform(screener_type: nil, instrument_ids: nil, symbols: nil)
      return unless market_open?

      # Convert instrument_ids string to array if needed
      instrument_ids = instrument_ids.split(",").map(&:to_i) if instrument_ids.is_a?(String)
      symbols = symbols.split(",") if symbols.is_a?(String)

      result = MarketHub::WebsocketTickStreamer.call(
        instrument_ids: instrument_ids,
        symbols: symbols,
      )

      if result[:success]
        Rails.logger.info(
          "[MarketHub::WebsocketTickStreamerJob] Started WebSocket stream for #{result[:subscribed_count]} instruments",
        )
        # Job will keep running - WebSocket connection is maintained
      else
        Rails.logger.error("[MarketHub::WebsocketTickStreamerJob] Failed: #{result[:error]}")
        # Retry if market is still open
        if market_open?
          MarketHub::WebsocketTickStreamerJob.set(wait: 10.seconds).perform_later(
            screener_type: screener_type,
            instrument_ids: instrument_ids,
            symbols: symbols,
          )
        end
      end
    rescue StandardError => e
      Rails.logger.error("[MarketHub::WebsocketTickStreamerJob] Error: #{e.message}")
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
