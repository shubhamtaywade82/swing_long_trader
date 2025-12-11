# frozen_string_literal: true

# Optional job for executing signals (order placement)
# Can be triggered by signal generation or scheduled
class ExecutorJob < ApplicationJob
  include JobLogging

  queue_as :default

  def perform(signal_hash, dry_run: nil)
    # Convert signal hash to proper format if needed
    signal = normalize_signal(signal_hash)

    # Execute via Swing::Executor
    result = Strategies::Swing::Executor.call(signal, dry_run: dry_run)

    if result[:success]
      Rails.logger.info(
        "[ExecutorJob] Order executed: " \
        "#{signal[:symbol]} #{signal[:direction]} #{signal[:qty]} @ #{signal[:entry_price]}"
      )

      # Send notification
      if AlgoConfig.fetch([:notifications, :telegram, :notify_entry])
        Telegram::Notifier.send_signal_alert(signal.merge(order_id: result[:order]&.id))
      end
    else
      Rails.logger.warn(
        "[ExecutorJob] Order execution failed: #{signal[:symbol]} - #{result[:error]}"
      )
    end

    result
  rescue StandardError => e
    Rails.logger.error("[ExecutorJob] Failed: #{e.message}")
    Telegram::Notifier.send_error_alert("Order execution failed: #{e.message}", context: 'ExecutorJob')
    raise
  end

  private

  def normalize_signal(signal_hash)
    # Ensure signal has all required fields
    signal_hash.symbolize_keys.tap do |signal|
      # Convert string keys to symbols if needed
      signal[:instrument_id] ||= signal[:instrument_id] || signal['instrument_id']
      signal[:symbol] ||= signal[:symbol] || signal['symbol']
      signal[:direction] = signal[:direction]&.to_sym || signal['direction']&.to_sym
      signal[:entry_price] ||= signal[:entry_price] || signal['entry_price']
      signal[:qty] ||= signal[:qty] || signal['qty']
    end
  end
end

