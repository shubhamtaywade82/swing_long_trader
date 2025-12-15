# frozen_string_literal: true

class MonitoringController < ApplicationController
  include SolidQueueHelper

  # Constants for queue health thresholds
  MAX_PENDING_JOBS_WARNING = 100
  MAX_FAILED_JOBS_WARNING = 50

  # @api public
  # Displays system monitoring information
  # @return [void] Renders monitoring/index view
  def index
    @jobs_status = get_jobs_status
    @system_health = get_system_health
    @queue_stats = get_solid_queue_stats
    @recent_errors = get_recent_errors
  end

  private

  def get_jobs_status
    {
      last_screener_run: get_last_job_run("Screeners::SwingScreenerJob"),
      last_analysis_run: get_last_job_run("Strategies::Swing::AnalysisJob"),
      last_entry_monitor: get_last_job_run("Strategies::Swing::EntryMonitorJob"),
      last_exit_monitor: get_last_job_run("Strategies::Swing::ExitMonitorJob"),
      last_candle_ingestion: get_last_job_run("Candles::DailyIngestorJob"),
    }
  end

  # @api private
  # Gets the last run time for a job class
  # @param [String] job_class Name of the job class
  # @return [Time, nil] Last run time or nil if not found
  def get_last_job_run(job_class)
    return nil unless solid_queue_installed?

    SolidQueue::Job
      .where("class_name LIKE ?", "%#{job_class.split('::').last}%")
      .order(created_at: :desc)
      .first
      &.finished_at
  rescue StandardError => e
    Rails.logger.error("[MonitoringController] Error fetching last job run: #{e.message}")
    nil
  end

  def get_system_health
    {
      database: check_database_connection,
      dhan_api: check_dhan_api_status,
      telegram: check_telegram_status,
      queue: check_queue_health,
    }
  end

  def check_database_connection
    ActiveRecord::Base.connection.execute("SELECT 1")
    "Healthy"
  rescue StandardError => e
    "Error: #{e.message}"
  end

  def check_dhan_api_status
    require "dhan_hq"
    profile = DhanHQ::Models::Profile.fetch
    if profile&.dhan_client_id.present?
      "Healthy (Client ID: #{profile.dhan_client_id})"
    else
      "Connected but no client ID"
    end
  rescue LoadError
    "DhanHQ gem not installed"
  rescue StandardError => e
    "Error: #{e.message}"
  end

  def check_telegram_status
    # Check if Telegram is configured
    return "Not configured (missing bot token or chat ID)" unless TelegramNotifier.enabled?

    # Try a simple API call to verify connectivity
    # Using getMe endpoint which doesn't send a message
    bot_token = ENV.fetch("TELEGRAM_BOT_TOKEN", nil)
    return "Not configured" unless bot_token.present?

    begin
      require "net/http"
      require "uri"
      uri = URI("https://api.telegram.org/bot#{bot_token}/getMe")
      response = Net::HTTP.get_response(uri)
      if response.code == "200"
        data = JSON.parse(response.body)
        if data["ok"]
          bot_username = data.dig("result", "username")
          "Healthy#{" (@#{bot_username})" if bot_username}"
        else
          "API Error: #{data['description']}"
        end
      else
        "HTTP Error: #{response.code}"
      end
    rescue JSON::ParserError => e
      "Error parsing response: #{e.message}"
    rescue StandardError => e
      "Error: #{e.message}"
    end
  end

  def check_queue_health
    return "Not installed" unless solid_queue_installed?

    stats = get_solid_queue_stats
    if stats[:pending] > MAX_PENDING_JOBS_WARNING || 
       stats[:failed] > MAX_FAILED_JOBS_WARNING
      "Warning: #{stats[:pending]} pending, #{stats[:failed]} failed"
    elsif !check_solid_queue_status[:worker_running]
      "Worker not running"
    else
      "Healthy"
    end
  rescue StandardError => e
    "Error: #{e.message}"
  end

  def get_recent_errors
    # Would query error logs or error tracking system
    []
  end
end
