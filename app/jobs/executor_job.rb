# frozen_string_literal: true

# Optional job for executing signals (order placement)
# Can be triggered by signal generation or scheduled
class ExecutorJob < ApplicationJob
  include JobLogging

  # Use dedicated execution queue for order placement
  queue_as :execution

  # Retry strategy: exponential backoff, max 3 attempts
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Don't retry on validation errors - discard them
  # Note: discard_on doesn't support :if keyword, so we discard all ArgumentErrors
  # For conditional discarding, we'd need to handle it in the perform method
  discard_on ArgumentError

  def perform(signal_hash, dry_run: nil)
    # Convert signal hash to proper format if needed
    signal = normalize_signal(signal_hash)

    # Execute via Swing::Executor
    result = Strategies::Swing::Executor.call(signal, dry_run: dry_run)

    mode = if result[:paper_trade]
             "PAPER"
           else
             (@dry_run ? "DRY RUN" : "LIVE")
           end
    if result[:success]
      Rails.logger.info(
        "[ExecutorJob] Order executed (#{mode}): " \
        "#{signal[:symbol]} #{signal[:direction]} #{signal[:qty]} @ #{signal[:entry_price]}",
      )

      # Send notification (only for live trades, paper trades send their own notifications)
      if !result[:paper_trade] && AlgoConfig.fetch(%i[notifications telegram notify_entry])
        order_id = result[:order]&.id || result[:position]&.id
        Telegram::Notifier.send_signal_alert(signal.merge(order_id: order_id))
      end
    else
      Rails.logger.warn(
        "[ExecutorJob] Order execution failed (#{mode}): #{signal[:symbol]} - #{result[:error]}",
      )
    end

    result
  rescue StandardError => e
    Rails.logger.error("[ExecutorJob] Failed: #{e.message}")
    Telegram::Notifier.send_error_alert("Order execution failed: #{e.message}", context: "ExecutorJob")
    raise
  end

  private

  def normalize_signal(signal_hash)
    # Ensure signal has all required fields
    signal_hash.symbolize_keys.tap do |signal|
      # Convert string keys to symbols if needed
      signal[:instrument_id] ||= signal[:instrument_id] || signal["instrument_id"]
      signal[:symbol] ||= signal[:symbol] || signal["symbol"]
      signal[:direction] = signal[:direction]&.to_sym || signal["direction"]&.to_sym
      signal[:entry_price] ||= signal[:entry_price] || signal["entry_price"]
      signal[:qty] ||= signal[:qty] || signal["qty"]
    end
  end
end
