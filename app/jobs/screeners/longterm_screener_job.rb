# frozen_string_literal: true

module Screeners
  class LongtermScreenerJob < ApplicationJob
    include JobLogging

    # Use dedicated screener queue
    queue_as :screener

    # Retry strategy: polynomial backoff, max 3 attempts (Rails 8.1+)
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(instruments: nil, limit: nil)
      # Log PID to verify job runs in worker process, not web process
      Rails.logger.info(
        "[Screeners::LongtermScreenerJob] Starting long-term screener " \
        "worker_pid=#{Process.pid} queue=#{queue_name}"
      )

      # Normalize limit parameter (handle string "ALL", nil, or integer)
      normalized_limit = if limit.nil? || limit.to_s.upcase == "ALL"
                           nil
                         else
                           limit.to_i
                         end
      normalized_limit = nil if normalized_limit.to_i <= 0

      # Calculate universe size
      universe_size = if instruments.respond_to?(:count)
                        instruments.count
                      elsif instruments.is_a?(Array)
                        instruments.size
                      else
                        Instrument.where(segment: %w[equity index], exchange: "NSE").count
                      end

      screener_run = ScreenerRun.create!(
        screener_type: "longterm",
        universe_size: universe_size,
        started_at: Time.current,
        status: "running",
        metrics: {},
      )

      Rails.logger.info("[Screeners::LongtermScreenerJob] Created ScreenerRun ##{screener_run.id}, universe_size: #{universe_size}, limit: #{normalized_limit || 'unlimited'}")

      begin
        # Enable persistence by default for background jobs
        candidates = LongtermScreener.call(
          instruments: instruments,
          limit: normalized_limit,
          persist_results: true,
          screener_run_id: screener_run.id,
        )

        # Update screener run with final metrics
        screener_run.update!(
          status: "completed",
          completed_at: Time.current,
        )
        screener_run.update_metrics!(
          eligible_count: candidates.size,
        )

        Rails.logger.info("[Screeners::LongtermScreenerJob] Found #{candidates.size} candidates")

        # Cache results for dashboard display (backward compatibility)
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
        screener_run.update!(
          status: "failed",
          completed_at: Time.current,
        )
        Rails.logger.error("[Screeners::LongtermScreenerJob] Failed: #{e.class} - #{e.message}")
        Rails.logger.error("[Screeners::LongtermScreenerJob] Backtrace: #{e.backtrace.first(10).join("\n")}")
        if defined?(Telegram::Notifier)
          Telegram::Notifier.send_error_alert("Long-term screener failed: #{e.message}",
                                              context: "LongtermScreenerJob")
        end
        raise
      end
    end
  end
end
