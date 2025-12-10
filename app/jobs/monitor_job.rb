# frozen_string_literal: true

class MonitorJob < ApplicationJob
  queue_as :default

  def perform
    checks = {
      database: check_database,
      dhan_api: check_dhan_api,
      telegram: check_telegram,
      candle_freshness: check_candle_freshness
    }

    failed_checks = checks.select { |_k, v| !v[:healthy] }

    if failed_checks.any?
      message = "⚠️ Health Check Failed:\n\n"
      failed_checks.each do |check, result|
        message += "❌ #{check}: #{result[:message]}\n"
      end
      Telegram::Notifier.send_error_alert(message, context: 'MonitorJob')
    end

    checks
  rescue StandardError => e
    Rails.logger.error("[MonitorJob] Failed: #{e.message}")
    raise
  end

  private

  def check_database
    Instrument.count
    { healthy: true, message: 'OK' }
  rescue StandardError => e
    { healthy: false, message: e.message }
  end

  def check_dhan_api
    # Simple check - try to get a quote
    instrument = Instrument.first
    return { healthy: false, message: 'No instruments' } unless instrument

    ltp = instrument.ltp
    { healthy: ltp.present?, message: ltp.present? ? 'OK' : 'No LTP response' }
  rescue StandardError => e
    { healthy: false, message: e.message }
  end

  def check_telegram
    { healthy: TelegramNotifier.enabled?, message: TelegramNotifier.enabled? ? 'OK' : 'Not configured' }
  rescue StandardError => e
    { healthy: false, message: e.message }
  end

  def check_candle_freshness
    latest = CandleSeriesRecord.order(timestamp: :desc).first
    return { healthy: false, message: 'No candles' } unless latest

    days_old = (Date.today - latest.timestamp.to_date).to_i
    healthy = days_old <= 2

    { healthy: healthy, message: healthy ? 'OK' : "Candles #{days_old} days old" }
  rescue StandardError => e
    { healthy: false, message: e.message }
  end
end

