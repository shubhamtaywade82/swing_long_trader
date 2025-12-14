# frozen_string_literal: true

module PaperTrading
  # Monitors paper trading positions for exit conditions
  # Runs periodically (every 30 min - 1 hour) to check SL/TP hits
  class ExitMonitorJob < ApplicationJob
    include JobLogging

    # Use monitoring queue for periodic checks
    queue_as :monitoring

    # Retry strategy: exponential backoff, max 2 attempts
    retry_on StandardError, wait: :exponentially_longer, attempts: 2

    def perform(portfolio_id: nil)
      return unless Rails.configuration.x.paper_trading.enabled

      portfolio = if portfolio_id
                    PaperPortfolio.find_by(id: portfolio_id)
                  else
                    PaperTrading::Portfolio.find_or_create_default
                  end

      return unless portfolio

      log_info("Checking exit conditions for paper trading positions")

      result = PaperTrading::Simulator.check_exits(portfolio: portfolio)

      log_info("Exit check completed: #{result[:exited]} positions exited out of #{result[:checked]} checked")
      result
    rescue StandardError => e
      log_error("Paper trading exit monitor failed: #{e.message}")
      Telegram::Notifier.send_error_alert(
        "Paper trading exit monitor failed: #{e.message}",
        context: "PaperTrading::ExitMonitorJob",
      )
      raise
    end
  end
end
