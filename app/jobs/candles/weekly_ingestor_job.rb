# frozen_string_literal: true

module Candles
  class WeeklyIngestorJob < ApplicationJob
    include JobLogging

    # Use data queue for data ingestion jobs
    queue_as :data_ingestion

    # Retry strategy: exponential backoff, max 3 attempts
    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform(instruments: nil, weeks_back: nil)
      result = WeeklyIngestor.call(instruments: instruments, weeks_back: weeks_back)

      if result[:success].positive?
        Rails.logger.info(
          "[Candles::WeeklyIngestorJob] Completed: " \
          "processed=#{result[:processed]}, " \
          "success=#{result[:success]}, " \
          "failed=#{result[:failed]}, " \
          "candles=#{result[:total_candles]}",
        )
      else
        Rails.logger.warn("[Candles::WeeklyIngestorJob] No candles ingested")
      end

      result
    rescue StandardError => e
      Rails.logger.error("[Candles::WeeklyIngestorJob] Failed: #{e.message}")
      Telegram::Notifier.send_error_alert("Weekly candle ingestion failed: #{e.message}", context: "WeeklyIngestorJob")
      raise
    end
  end
end
