# frozen_string_literal: true

# Optional job for sending notifications via Telegram
# Can be used to queue notifications instead of sending synchronously
# Useful for high-volume scenarios or when you want to batch notifications
class NotifierJob < ApplicationJob
  include JobLogging

  # Use dedicated notifier queue (low priority, failures are non-critical)
  queue_as :notifier

  # Don't retry notification failures - they're non-critical
  discard_on StandardError

  def perform(notification_type, payload = {})
    case notification_type.to_sym
    when :daily_candidates
      Telegram::Notifier.send_daily_candidates(payload[:candidates] || [])
    when :signal_alert
      Telegram::Notifier.send_signal_alert(payload[:signal] || {})
    when :exit_alert
      Telegram::Notifier.send_exit_alert(payload[:exit_info] || {})
    when :error_alert
      Telegram::Notifier.send_error_alert(
        payload[:message] || "",
        context: payload[:context] || "NotifierJob",
      )
    when :portfolio_snapshot
      Telegram::Notifier.send_portfolio_snapshot(payload[:portfolio] || {})
    when :message
      Telegram::Notifier.send_message(payload[:message] || "")
    else
      Rails.logger.warn("[NotifierJob] Unknown notification type: #{notification_type}")
    end
  rescue StandardError => e
    Rails.logger.error("[NotifierJob] Failed: #{e.message}")
    # Don't raise - notification failures shouldn't break the job queue
  end
end
