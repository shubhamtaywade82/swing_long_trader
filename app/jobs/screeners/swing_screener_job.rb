# frozen_string_literal: true

module Screeners
  class SwingScreenerJob < ApplicationJob
    include JobLogging

    queue_as :default

    def perform(instruments: nil, limit: nil)
      candidates = SwingScreener.call(instruments: instruments, limit: limit)

      Rails.logger.info("[Screeners::SwingScreenerJob] Found #{candidates.size} candidates")

      # Send top 10 to Telegram
      if candidates.any? && AlgoConfig.fetch([:notifications, :telegram, :notify_screener_results])
        Telegram::Notifier.send_daily_candidates(candidates.first(10))
      end

      candidates
    rescue StandardError => e
      Rails.logger.error("[Screeners::SwingScreenerJob] Failed: #{e.message}")
      Telegram::Notifier.send_error_alert("Swing screener failed: #{e.message}", context: 'SwingScreenerJob')
      raise
    end
  end
end

