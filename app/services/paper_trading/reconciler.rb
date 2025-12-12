# frozen_string_literal: true

module PaperTrading
  # Performs daily mark-to-market reconciliation
  class Reconciler < ApplicationService
    def self.call(portfolio: nil)
      portfolio ||= PaperTrading::Portfolio.find_or_create_default
      new(portfolio: portfolio).call
    end

    def initialize(portfolio:)
      @portfolio = portfolio
    end

    def call
      log_info("Starting mark-to-market reconciliation")

      # Update all open positions with current prices
      update_all_positions

      # Calculate unrealized P&L
      calculate_unrealized_pnl

      # Update portfolio equity
      @portfolio.update_equity!

      # Update drawdown
      @portfolio.update_drawdown!

      # Generate summary
      summary = generate_summary

      # Send Telegram notification
      send_daily_summary(summary)

      log_info("Mark-to-market completed: Equity ₹#{@portfolio.total_equity.round(2)}")
      summary
    rescue StandardError => e
      log_error("Reconciliation failed: #{e.message}")
      raise
    end

    private

    def update_all_positions
      open_positions = @portfolio.open_positions.includes(:instrument)

      open_positions.each do |position|
        latest_candle = CandleSeriesRecord
                        .where(instrument_id: position.instrument_id, timeframe: "1D")
                        .order(timestamp: :desc)
                        .first

        next unless latest_candle

        position.update_current_price!(latest_candle.close)
      end
    end

    def calculate_unrealized_pnl
      unrealized_pnl = @portfolio.open_positions.sum(&:unrealized_pnl)
      @portfolio.update!(pnl_unrealized: unrealized_pnl)
    end

    def generate_summary
      {
        portfolio_name: @portfolio.name,
        capital: @portfolio.capital.round(2),
        total_equity: @portfolio.total_equity.round(2),
        pnl_realized: @portfolio.pnl_realized.round(2),
        pnl_unrealized: @portfolio.pnl_unrealized.round(2),
        total_pnl: (@portfolio.pnl_realized + @portfolio.pnl_unrealized).round(2),
        max_drawdown: @portfolio.max_drawdown.round(2),
        utilization_pct: @portfolio.utilization_pct,
        open_positions_count: @portfolio.open_positions.count,
        closed_positions_count: @portfolio.closed_positions.count,
        total_exposure: @portfolio.total_exposure.round(2),
        available_capital: @portfolio.available_capital.round(2),
      }
    end

    def send_daily_summary(summary)
      return unless Telegram::Notifier.enabled?

      message = "📊 <b>DAILY PAPER TRADING SUMMARY</b>\n\n"
      message += "Portfolio: #{summary[:portfolio_name]}\n"
      message += "Capital: ₹#{summary[:capital]}\n"
      message += "Total Equity: ₹#{summary[:total_equity]}\n"
      message += "Realized P&L: ₹#{summary[:pnl_realized]}\n"
      message += "Unrealized P&L: ₹#{summary[:pnl_unrealized]}\n"
      message += "Total P&L: ₹#{summary[:total_pnl]}\n"
      message += "Max Drawdown: #{summary[:max_drawdown]}%\n"
      message += "Utilization: #{summary[:utilization_pct]}%\n"
      message += "Open Positions: #{summary[:open_positions_count]}\n"
      message += "Closed Positions: #{summary[:closed_positions_count]}\n"
      message += "Total Exposure: ₹#{summary[:total_exposure]}\n"
      message += "Available Capital: ₹#{summary[:available_capital]}"

      Telegram::Notifier.send_error_alert(message, context: "Daily Paper Trading Summary")
    rescue StandardError => e
      log_error("Failed to send daily summary: #{e.message}")
    end
  end
end
