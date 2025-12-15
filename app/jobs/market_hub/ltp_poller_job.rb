# frozen_string_literal: true

module MarketHub
  # Background job to poll and broadcast LTPs for screener stocks
  class LtpPollerJob < ApplicationJob
    queue_as :monitoring

    # Poll every 5 seconds during market hours
    POLL_INTERVAL = 5.seconds

    def perform(screener_type: nil, instrument_ids: nil, symbols: nil)
      return unless market_open?

      result = MarketHub::LtpBroadcaster.call(
        screener_type: screener_type,
        instrument_ids: instrument_ids,
        symbols: symbols,
      )

      if result[:success]
        Rails.logger.debug("[MarketHub::LtpPollerJob] Updated #{result[:updated_count]} LTPs")
      else
        Rails.logger.warn("[MarketHub::LtpPollerJob] Failed: #{result[:error]}")
      end

      # Schedule next poll if market is still open
      if market_open?
        MarketHub::LtpPollerJob.set(wait: POLL_INTERVAL).perform_later(
          screener_type: screener_type,
          instrument_ids: instrument_ids,
          symbols: symbols,
        )
      end
    rescue StandardError => e
      Rails.logger.error("[MarketHub::LtpPollerJob] Error: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
    end

    private

    def market_open?
      # Indian market hours: 9:15 AM to 3:30 PM IST
      now = Time.current.in_time_zone("Asia/Kolkata")
      return false unless now.wday.between?(1, 5) # Monday to Friday

      market_open = now.change(hour: 9, min: 15, sec: 0)
      market_close = now.change(hour: 15, min: 30, sec: 0)

      now >= market_open && now <= market_close
    end
  end
end
