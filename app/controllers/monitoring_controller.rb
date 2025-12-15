# frozen_string_literal: true

class MonitoringController < ApplicationController
  include SolidQueueHelper

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

  def get_last_job_run(_job_class)
    # This would query SolidQueue or your job tracking system
    # For now, return a placeholder
    "Not tracked"
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
    if stats[:pending] > 100 || stats[:failed] > 50
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
