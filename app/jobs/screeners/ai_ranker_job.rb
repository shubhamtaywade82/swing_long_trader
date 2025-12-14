# frozen_string_literal: true

module Screeners
  class AIRankerJob < ApplicationJob
    # Use dedicated AI queue for rate limiting and cost control
    queue_as :ai_evaluation

    # Retry strategy: exponential backoff, max 2 attempts (to control AI costs)
    retry_on StandardError, wait: [30.seconds, 60.seconds], attempts: 2

    # Don't retry on rate limit errors (will be handled by fallback)
    discard_on RuntimeError, if: ->(error) { error.message.include?("rate limit") }

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
