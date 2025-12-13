# frozen_string_literal: true

module Screeners
  class LongtermScreenerJob < ApplicationJob
    include JobLogging

    queue_as :default

    def perform(instruments: nil, limit: nil)
      # Enable persistence by default for background jobs
      candidates = LongtermScreener.call(instruments: instruments, limit: limit, persist_results: true)

      Rails.logger.info("[Screeners::LongtermScreenerJob] Found #{candidates.size} candidates")

      # Cache results for dashboard display
      cache_key = "longterm_screener_results_#{Date.current}"
      Rails.cache.write(cache_key, candidates, expires_in: 24.hours)
      Rails.cache.write("#{cache_key}_timestamp", Time.current, expires_in: 24.hours)

      # Broadcast update to dashboard
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_update",
          screener_type: "longterm",
          candidate_count: candidates.size,
        },
      )

      candidates
    rescue StandardError => e
      Rails.logger.error("[Screeners::LongtermScreenerJob] Failed: #{e.message}")
      if defined?(Telegram::Notifier)
        Telegram::Notifier.send_error_alert("Long-term screener failed: #{e.message}",
                                            context: "LongtermScreenerJob")
      end
      raise
    end
  end
end
