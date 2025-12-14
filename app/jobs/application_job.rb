# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Retry on standard errors with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # Log job execution time
  around_perform :log_job_duration

  # Alert on job failures
  after_perform :log_success
  rescue_from StandardError, with: :handle_job_failure

  private

  def log_job_duration
    start_time = Time.current
    log_info("Job started: #{self.class.name}")
    yield
    duration = ((Time.current - start_time) * 1000).round(2)
    log_info("Job completed: #{self.class.name} (#{duration}ms)")
  rescue StandardError => e
    duration = ((Time.current - start_time) * 1000).round(2)
    log_error("Job failed: #{self.class.name} (#{duration}ms) - #{e.class}: #{e.message}")
    raise
  end

  def log_success
    log_info("Job succeeded: #{self.class.name}")
  end

  def handle_job_failure(error)
    log_error("Job failed: #{self.class.name} - #{error.class}: #{error.message}")
    log_error("Backtrace: #{error.backtrace.first(5).join("\n")}")

    # Alert to Telegram if enabled
    if TelegramNotifier.enabled?
      message = "❌ Job Failed: #{self.class.name}\n\n" \
                "Error: #{error.class}\n" \
                "Message: #{error.message}\n\n" \
                "Retries remaining: #{executions}"
      TelegramNotifier.send_message(message)
    end

    # Re-raise to trigger retry mechanism
    raise
  end
end
