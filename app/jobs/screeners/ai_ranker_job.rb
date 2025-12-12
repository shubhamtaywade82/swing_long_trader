# frozen_string_literal: true

module Screeners
  class AIRankerJob < ApplicationJob
    queue_as :default

    def perform(candidates, limit: nil)
      ranked = AIRanker.call(candidates: candidates, limit: limit)

      Rails.logger.info("[Screeners::AIRankerJob] Ranked #{ranked.size} candidates")

      ranked
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIRankerJob] Failed: #{e.message}")
      Telegram::Notifier.send_error_alert("AI ranker failed: #{e.message}", context: "AIRankerJob")
      raise
    end
  end
end
