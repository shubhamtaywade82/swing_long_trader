# frozen_string_literal: true

class MonitorJob < ApplicationJob
  include JobLogging

  queue_as :default

  def perform
    checks = {
      database: check_database,
      dhan_api: check_dhan_api,
      telegram: check_telegram,
      candle_freshness: check_candle_freshness,
      job_queue: check_job_queue,
      job_duration: check_job_duration,
      openai_cost: check_openai_cost,
    }

    failed_checks = checks.reject { |_k, v| v[:healthy] }

    if failed_checks.any?
      message = "⚠️ Health Check Failed:\n\n"
      failed_checks.each do |check, result|
        message += "❌ #{check}: #{result[:message]}\n"
      end
      Telegram::Notifier.send_error_alert(message, context: "MonitorJob")
    end

    checks
  rescue StandardError => e
    Rails.logger.error("[MonitorJob] Failed: #{e.message}")
    raise
  end

  private

  def check_database
    Instrument.count
    { healthy: true, message: "OK" }
  rescue StandardError => e
    { healthy: false, message: e.message }
  end

  def check_dhan_api
    # Simple check - try to get a quote
    instrument = Instrument.first
    return { healthy: false, message: "No instruments" } unless instrument

    ltp = instrument.ltp
    { healthy: ltp.present?, message: ltp.present? ? "OK" : "No LTP response" }
  rescue StandardError => e
    { healthy: false, message: e.message }
  end

  def check_telegram
    { healthy: TelegramNotifier.enabled?, message: TelegramNotifier.enabled? ? "OK" : "Not configured" }
  rescue StandardError => e
    { healthy: false, message: e.message }
  end

  def check_candle_freshness
    latest = CandleSeriesRecord.order(timestamp: :desc).first
    return { healthy: false, message: "No candles" } unless latest

    days_old = (Time.zone.today - latest.timestamp.to_date).to_i
    healthy = days_old <= 2

    { healthy: healthy, message: healthy ? "OK" : "Candles #{days_old} days old" }
  rescue StandardError => e
    { healthy: false, message: e.message }
  end

  def check_job_queue
    return { healthy: true, message: "SolidQueue not installed" } unless solid_queue_installed?

    pending = SolidQueue::Job.where(finished_at: nil).where("scheduled_at IS NULL OR scheduled_at <= ?",
                                                            Time.current).count
    failed = SolidQueue::FailedExecution.count
    running = SolidQueue::ClaimedExecution.count

    queue_healthy = pending < 100 && failed < 50
    message = "Pending: #{pending}, Running: #{running}, Failed: #{failed}"

    { healthy: queue_healthy, message: message }
  rescue StandardError => e
    { healthy: false, message: e.message }
  end

  def check_job_duration
    return { healthy: true, message: "N/A" } unless solid_queue_installed?

    # Get average duration for recent completed jobs
    recent_jobs = SolidQueue::Job
                  .where.not(finished_at: nil)
                  .where("finished_at > ?", 1.hour.ago)
                  .where.not(created_at: nil)
                  .limit(100)

    return { healthy: true, message: "No recent jobs" } if recent_jobs.empty?

    durations = recent_jobs.filter_map do |job|
      next unless job.created_at && job.finished_at

      (job.finished_at - job.created_at).to_f
    end

    return { healthy: true, message: "No duration data" } if durations.empty?

    avg_duration = durations.sum / durations.size
    max_duration = durations.max

    # Alert if average > 5 minutes or max > 10 minutes
    healthy = avg_duration < 300 && max_duration < 600
    message = "Avg: #{avg_duration.round(1)}s, Max: #{max_duration.round(1)}s"

    { healthy: healthy, message: message }
  rescue StandardError => e
    { healthy: false, message: e.message }
  end

  def check_openai_cost
    return { healthy: true, message: "OpenAI not configured" } if ENV["OPENAI_API_KEY"].blank?

    cost_config = AlgoConfig.fetch(%i[openai cost_monitoring]) || {}
    return { healthy: true, message: "Cost monitoring disabled" } unless cost_config[:enabled]

    today = Time.zone.today
    daily_cost = Metrics::Tracker.get_openai_daily_cost(today)

    # Get thresholds
    daily_threshold = cost_config[:daily_threshold] || 10.0
    weekly_threshold = cost_config[:weekly_threshold] || 50.0
    monthly_threshold = cost_config[:monthly_threshold] || 200.0

    # Calculate weekly and monthly costs
    week_start = today.beginning_of_week
    weekly_cost = calculate_weekly_cost(week_start, today)
    month_start = today.beginning_of_month
    monthly_cost = calculate_monthly_cost(month_start, today)

    # Check thresholds
    warnings = []
    warnings << "Daily: $#{daily_cost.round(4)} >= $#{daily_threshold}" if daily_cost >= daily_threshold
    warnings << "Weekly: $#{weekly_cost.round(4)} >= $#{weekly_threshold}" if weekly_cost >= weekly_threshold
    warnings << "Monthly: $#{monthly_cost.round(4)} >= $#{monthly_threshold}" if monthly_cost >= monthly_threshold

    healthy = warnings.empty?
    message = if warnings.any?
                warnings.join(", ")
              else
                "Daily: $#{daily_cost.round(4)}, Weekly: $#{weekly_cost.round(4)}, Monthly: $#{monthly_cost.round(4)}"
              end

    { healthy: healthy, message: message }
  rescue StandardError => e
    { healthy: false, message: e.message }
  end

  def calculate_weekly_cost(week_start, current_date)
    total = 0.0
    (week_start..current_date).each do |date|
      total += Metrics::Tracker.get_openai_daily_cost(date)
    end
    total
  end

  def calculate_monthly_cost(month_start, current_date)
    total = 0.0
    (month_start..current_date).each do |date|
      total += Metrics::Tracker.get_openai_daily_cost(date)
    end
    total
  end

  def solid_queue_installed?
    ActiveRecord::Base.connection.table_exists?("solid_queue_jobs")
  end
end
