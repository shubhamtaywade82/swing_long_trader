# frozen_string_literal: true

class MonitorJob < ApplicationJob
  include JobLogging

  # Use monitoring queue for health checks
  queue_as :monitoring

  # Don't retry monitoring failures - they're informational
  discard_on StandardError

  def perform
    checks = {
      database: check_database,
      dhan_api: check_dhan_api,
      telegram: check_telegram,
      candle_freshness: check_candle_freshness,
      job_queue: check_job_queue,
      job_duration: check_job_duration,
      openai_cost: check_openai_cost,
      dhan_expirations: check_dhan_expirations,
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
    return { healthy: false, message: "No candles - Run: rails runner 'Candles::DailyIngestor.call'" } unless latest

    days_old = (Time.zone.today - latest.timestamp.to_date).to_i

    # Account for weekends and holidays - markets are closed on weekends
    # Allow up to 4 days (which could be Thu -> Mon = 4 days including weekend)
    # But flag if > 5 days (likely a real issue)
    trading_days_old = count_trading_days_since(latest.timestamp.to_date)
    healthy = days_old <= 4 && trading_days_old <= 2

    message = if healthy
                "OK (#{days_old} calendar days, #{trading_days_old} trading days)"
              else
                # Add actionable suggestions for stale candles
                suggestion = if days_old > 365
                                " - CRITICAL: Candles >1yr old. Check ingestion jobs or run: rails runner 'Candles::DailyIngestor.call(days_back: 800)'"
                              elsif days_old > 30
                                " - Check scheduled jobs or run: rails runner 'Candles::DailyIngestorJob.perform_later'"
                              else
                                " - Run: rails runner 'Candles::DailyIngestor.call'"
                              end
                "Candles #{days_old} days old (#{trading_days_old} trading days)#{suggestion}"
              end

    { healthy: healthy, message: message }
  rescue StandardError => e
    { healthy: false, message: e.message }
  end

  def count_trading_days_since(date)
    # Count weekdays (Mon-Fri) since the given date, excluding today
    today = Time.zone.today
    return 0 if date >= today

    count = 0
    current_date = date + 1.day
    while current_date < today
      # Monday = 1, Friday = 5
      count += 1 if (1..5).include?(current_date.wday)
      current_date += 1.day
    end
    count
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

    # Group durations by job class to identify problematic jobs
    job_durations = {}
    recent_jobs.each do |job|
      next unless job.created_at && job.finished_at

      duration = (job.finished_at - job.created_at).to_f
      class_name = job.class_name || "Unknown"
      job_durations[class_name] ||= []
      job_durations[class_name] << duration
    end

    return { healthy: true, message: "No duration data" } if job_durations.empty?

    # Calculate overall stats
    all_durations = job_durations.values.flatten
    avg_duration = all_durations.sum / all_durations.size
    max_duration = all_durations.max

    # Find slow jobs (max > 10 minutes or avg > 5 minutes for that class)
    slow_jobs = job_durations.select do |class_name, durations|
      class_avg = durations.sum / durations.size
      class_max = durations.max
      class_max > 600 || class_avg > 300
    end

    # Alert if average > 5 minutes or max > 10 minutes
    healthy = avg_duration < 300 && max_duration < 600

    message = if healthy
                "Avg: #{avg_duration.round(1)}s, Max: #{max_duration.round(1)}s"
              else
                # Limit to top 3 slowest jobs to keep message concise
                slow_job_info = slow_jobs.sort_by do |_class_name, durations|
                  durations.max
                end.reverse.first(3).map do |class_name, durations|
                  class_avg = durations.sum / durations.size
                  class_max = durations.max
                  "#{class_name.split('::').last}: avg=#{class_avg.round(1)}s, max=#{class_max.round(1)}s"
                end.join(", ")
                more_count = slow_jobs.size - 3
                more_text = more_count.positive? ? " (+#{more_count} more)" : ""
                "Avg: #{avg_duration.round(1)}s, Max: #{max_duration.round(1)}s" \
                  " (Slow: #{slow_job_info}#{more_text})"
              end

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

  def check_dhan_expirations
    expirations = AboutController.new.send(:check_dhan_expirations)
    critical = expirations.select { |e| e[:severity] == "critical" }
    warnings = expirations.select { |e| e[:severity] == "warning" }

    if critical.any?
      message = "🚨 CRITICAL: DhanHQ Expirations:\n\n"
      critical.each do |exp|
        message += "❌ #{exp[:message]}\n"
      end
      Telegram::Notifier.send_error_alert(message, context: "MonitorJob - DhanHQ Expiration")
      { healthy: false, message: "#{critical.size} critical expiration(s)" }
    elsif warnings.any?
      message = "⚠️ WARNING: DhanHQ Expiring Soon:\n\n"
      warnings.each do |exp|
        message += "⚠️ #{exp[:message]}\n"
      end
      Telegram::Notifier.send_error_alert(message, context: "MonitorJob - DhanHQ Expiration Warning")
      { healthy: true, message: "#{warnings.size} warning(s)" }
    else
      { healthy: true, message: "OK" }
    end
  rescue StandardError => e
    { healthy: false, message: "Error: #{e.message}" }
  end

  def solid_queue_installed?
    ActiveRecord::Base.connection.table_exists?("solid_queue_jobs")
  end
end
