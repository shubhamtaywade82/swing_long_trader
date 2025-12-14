# frozen_string_literal: true

module AIConfidence
  # Background job to run AI confidence calibration
  class CalibrationJob < ApplicationJob
    include JobLogging

    # Use background queue for analysis jobs
    queue_as :background

    # Retry strategy: exponential backoff, max 2 attempts
    retry_on StandardError, wait: :exponentially_longer, attempts: 2

    def perform(scope: nil, min_outcomes: 50)
      Rails.logger.info("[AIConfidence::CalibrationJob] Starting calibration")

      outcome_scope = scope || TradeOutcome.closed
      total_outcomes = outcome_scope.count

      if total_outcomes < min_outcomes
        Rails.logger.warn(
          "[AIConfidence::CalibrationJob] Insufficient data: #{total_outcomes} outcomes " \
          "(need #{min_outcomes})"
        )
        return {
          success: false,
          insufficient_data: true,
          total_outcomes: total_outcomes,
          min_required: min_outcomes,
        }
      end

      # Run calibration
      result = Calibrator.call(scope: outcome_scope, min_outcomes: min_outcomes)

      if result[:success]
        Rails.logger.info(
          "[AIConfidence::CalibrationJob] Calibration complete: " \
          "Win rate: #{result.dig(:calibration, :overall_win_rate)}%, " \
          "Expectancy: #{result.dig(:calibration, :overall_expectancy)}, " \
          "Correlation: #{result.dig(:calibration, :confidence_correlation)}"
        )

        # Generate threshold optimization recommendations
        threshold_result = ThresholdOptimizer.call(calibration_result: result)

        # Send summary to Telegram if configured
        if AlgoConfig.fetch(%i[notifications telegram notify_calibration])
          send_calibration_summary(result, threshold_result)
        end
      else
        Rails.logger.error("[AIConfidence::CalibrationJob] Calibration failed: #{result[:error]}")
      end

      result
    rescue StandardError => e
      Rails.logger.error("[AIConfidence::CalibrationJob] Failed: #{e.message}")
      Telegram::Notifier.send_error_alert(
        "AI calibration failed: #{e.message}",
        context: "AICalibrationJob",
      )
      raise
    end

    private

    def send_calibration_summary(calibration_result, threshold_result)
      message = "📊 <b>AI Confidence Calibration</b>\n\n"
      message += "Total Outcomes: #{calibration_result[:total_outcomes]}\n"
      message += "Win Rate: #{calibration_result.dig(:calibration, :overall_win_rate)}%\n"
      message += "Expectancy: #{calibration_result.dig(:calibration, :overall_expectancy)}\n"
      message += "Correlation: #{calibration_result.dig(:calibration, :confidence_correlation)}\n\n"

      if threshold_result[:success]
        message += "<b>Threshold Recommendation:</b>\n"
        message += "#{threshold_result[:rationale]}\n"
      end

      if calibration_result[:recommendations]&.any?
        message += "\n<b>Recommendations:</b>\n"
        calibration_result[:recommendations].first(3).each do |rec|
          message += "• #{rec[:message]}\n"
        end
      end

      Telegram::Notifier.send_message(message, parse_mode: "HTML")
    rescue StandardError => e
      Rails.logger.error("[AIConfidence::CalibrationJob] Failed to send summary: #{e.message}")
    end
  end
end
