# frozen_string_literal: true

module PaperTrading
  # Performs daily mark-to-market reconciliation for paper trading
  # Runs after market close to update all positions and calculate P&L
  class ReconciliationJob < ApplicationJob
    include JobLogging

    # Use monitoring queue for reconciliation jobs
    queue_as :monitoring

    # Retry strategy: exponential backoff, max 2 attempts
    retry_on StandardError, wait: :polynomially_longer, attempts: 2

    def perform(portfolio_id: nil)
      return unless Rails.configuration.x.paper_trading.enabled

      portfolio = if portfolio_id
                    PaperPortfolio.find_by(id: portfolio_id)
                  else
                    PaperTrading::Portfolio.find_or_create_default
                  end

      return unless portfolio

      log_info("Starting daily mark-to-market reconciliation")

      summary = PaperTrading::Reconciler.call(portfolio: portfolio)

      log_info("Reconciliation completed: Equity ₹#{summary[:total_equity]}")
      summary
    rescue StandardError => e
      log_error("Paper trading reconciliation failed: #{e.message}")
      Telegram::Notifier.send_error_alert(
        "Paper trading reconciliation failed: #{e.message}",
        context: "PaperTrading::ReconciliationJob",
      )
      raise
    end
  end
end
