# frozen_string_literal: true

module Candles
  class DailyIngestorJob < ApplicationJob
    queue_as :default

    def perform(instruments: nil, days_back: nil)
      result = DailyIngestor.call(instruments: instruments, days_back: days_back)

      if result[:success] > 0
        Rails.logger.info(
          "[Candles::DailyIngestorJob] Completed: " \
          "processed=#{result[:processed]}, " \
          "success=#{result[:success]}, " \
          "failed=#{result[:failed]}, " \
          "candles=#{result[:total_candles]}"
        )
      else
        Rails.logger.warn("[Candles::DailyIngestorJob] No candles ingested")
      end

      result
    rescue StandardError => e
      Rails.logger.error("[Candles::DailyIngestorJob] Failed: #{e.message}")
      Telegram::Notifier.send_error_alert("Daily candle ingestion failed: #{e.message}", context: 'DailyIngestorJob')
      raise
    end
  end
end

