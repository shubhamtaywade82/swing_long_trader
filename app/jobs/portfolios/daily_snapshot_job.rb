# frozen_string_literal: true

module Portfolios
  # Job to create daily portfolio snapshots
  # Runs at end of trading day to capture portfolio state
  class DailySnapshotJob < ApplicationJob
    include JobLogging

    # Use background queue for snapshot jobs
    queue_as :background

    # Retry strategy: exponential backoff, max 2 attempts
    retry_on StandardError, wait: :exponentially_longer, attempts: 2

    def perform(date: nil, portfolio_type: "all")
      date ||= Time.zone.today

      result = Portfolios::DailySnapshot.create_for_date(
        date: date,
        portfolio_type: portfolio_type,
      )

      if result[:live] && result[:live][:success]
        Rails.logger.info(
          "[Portfolios::DailySnapshotJob] Live portfolio snapshot created for #{date}",
        )
      end

      if result[:paper] && result[:paper][:success]
        Rails.logger.info(
          "[Portfolios::DailySnapshotJob] Paper portfolio snapshot created for #{date}",
        )
      end

      result
    rescue StandardError => e
      Rails.logger.error("[Portfolios::DailySnapshotJob] Failed: #{e.message}")
      Telegram::Notifier.send_error_alert(
        "Daily portfolio snapshot failed: #{e.message}",
        context: "DailySnapshotJob",
      )
      raise
    end
  end
end
