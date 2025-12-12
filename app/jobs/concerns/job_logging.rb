# frozen_string_literal: true

module JobLogging
  extend ActiveSupport::Concern

  included do
    around_perform :track_job_execution
    rescue_from StandardError, with: :handle_job_error
  end

  private

  def track_job_execution
    start_time = Time.current
    job_name = self.class.name

    Rails.logger.info("[#{job_name}] Starting execution")

    yield

    duration = Time.current - start_time
    Rails.logger.info("[#{job_name}] Completed in #{duration.round(2)}s")

    Metrics::Tracker.track_job_duration(job_name, duration)
  rescue StandardError => e
    duration = Time.current - start_time
    Rails.logger.error("[#{self.class.name}] Failed after #{duration.round(2)}s: #{e.message}")
    raise
  end

  def handle_job_error(error)
    job_name = self.class.name
    Metrics::Tracker.track_failed_job(job_name)

    Rails.logger.error("[#{job_name}] Error: #{error.class} - #{error.message}")
    Rails.logger.error("[#{job_name}] Backtrace: #{error.backtrace.first(10).join("\n")}")

    # Send alert to Telegram
    Telegram::Notifier.send_error_alert(
      "Job failed: #{job_name}\n\n#{error.message}",
      context: job_name,
    )

    raise error
  end
end
