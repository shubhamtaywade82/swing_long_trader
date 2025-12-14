# frozen_string_literal: true

module Screeners
  # Automated screener job that runs during market hours
  # Screens the complete universe and persists results incrementally
  class AutomatedScreenerJob < ApplicationJob
    include JobLogging

    # Use dedicated screener queue
    queue_as :screener

    # Retry strategy: exponential backoff, max 2 attempts (scheduled job)
    retry_on StandardError, wait: :polynomially_longer, attempts: 2

    def perform(screener_type: "swing")
      # Check if market is open
      unless MarketHours::Checker.market_open?
        Rails.logger.info("[Screeners::AutomatedScreenerJob] Market is closed, skipping #{screener_type} screener")
        return
      end

      Rails.logger.info("[Screeners::AutomatedScreenerJob] Starting automated #{screener_type} screener during market hours")

      # Run screener with full universe (no limit) and persistence enabled
      candidates = case screener_type
                   when "swing"
                     SwingScreener.call(limit: nil, persist_results: true)
                   when "longterm"
                     LongtermScreener.call(limit: nil, persist_results: true)
                   else
                     Rails.logger.error("[Screeners::AutomatedScreenerJob] Unknown screener type: #{screener_type}")
                     return
                   end

      Rails.logger.info("[Screeners::AutomatedScreenerJob] Completed #{screener_type} screener: #{candidates.size} candidates found")

      # Broadcast completion
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_complete",
          screener_type: screener_type,
          candidate_count: candidates.size,
          message: "Automated #{screener_type} screener completed during market hours",
        },
      )

      candidates
    rescue StandardError => e
      Rails.logger.error("[Screeners::AutomatedScreenerJob] Failed: #{e.message}")
      Rails.logger.error("[Screeners::AutomatedScreenerJob] Backtrace: #{e.backtrace.first(10).join("\n")}")
      raise
    end
  end
end
