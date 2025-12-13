# frozen_string_literal: true

module Screeners
  class SwingScreenerJob < ApplicationJob
    include JobLogging

    queue_as :default

    def perform(instruments: nil, limit: nil)
      # Enable persistence by default for background jobs
      candidates = SwingScreener.call(instruments: instruments, limit: limit, persist_results: true)

      Rails.logger.info("[Screeners::SwingScreenerJob] Found #{candidates.size} candidates")

      # Cache results for dashboard display
      cache_key = "swing_screener_results_#{Date.current}"
      Rails.cache.write(cache_key, candidates, expires_in: 24.hours)
      Rails.cache.write("#{cache_key}_timestamp", Time.current, expires_in: 24.hours)

      # Broadcast update to dashboard
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_update",
          screener_type: "swing",
          candidate_count: candidates.size,
        },
      )

      # Send top 10 to Telegram
      if candidates.any? && AlgoConfig.fetch(%i[notifications telegram notify_screener_results])
        Telegram::Notifier.send_daily_candidates(candidates.first(10))
      end

      # Optionally trigger swing analysis job for top candidates
      if candidates.any? && AlgoConfig.fetch(%i[swing_trading strategy auto_analyze])
        candidate_ids = candidates.first(20).pluck(:instrument_id)
        Strategies::Swing::AnalysisJob.perform_later(candidate_ids)
        Rails.logger.info("[Screeners::SwingScreenerJob] Triggered analysis job for #{candidate_ids.size} candidates")
      end

      candidates
    rescue StandardError => e
      Rails.logger.error("[Screeners::SwingScreenerJob] Failed: #{e.message}")

      # Mark as failed
      progress_key = "swing_screener_progress_#{Date.current}"
      Rails.cache.write(progress_key, {
        status: "failed",
        error: e.message,
        failed_at: Time.current.iso8601,
      }, expires_in: 1.hour)

      Telegram::Notifier.send_error_alert("Swing screener failed: #{e.message}", context: "SwingScreenerJob")
      raise
    end
  end
end
