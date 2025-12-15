# frozen_string_literal: true

module BalanceHelper
  extend ActiveSupport::Concern

  private

  def get_balance_info(mode)
    if mode == "paper"
      # Use CapitalAllocationPortfolio and ensure it's initialized
      portfolio = CapitalAllocationPortfolio.paper.active.first

      # Always ensure portfolio is initialized and capital is allocated
      initializer_result = Portfolios::PaperPortfolioInitializer.call
      if initializer_result[:success]
        portfolio = initializer_result[:portfolio]
      else
        Rails.logger.error("[BalanceHelper] Failed to initialize paper portfolio: #{initializer_result[:error]}")
        # Return zero balance if initialization fails
        return {
          available_balance: 0,
          total_equity: 0,
          capital: 0,
          reserved_capital: 0,
          unrealized_pnl: 0,
          realized_pnl: 0,
          total_exposure: 0,
          utilization_pct: 0,
          type: "paper",
        }
      end

      # Ensure capital is allocated if swing_capital is still zero
      if portfolio.swing_capital.zero? && portfolio.total_equity.positive?
        Rails.logger.info("[BalanceHelper] Swing capital is zero, triggering rebalance...")
        portfolio.rebalance_capital!
        portfolio.reload
      end

      # Recalculate from actual positions (unified Position model)
      open_positions = Position.paper.open.includes(:instrument)
      calculated_exposure = open_positions.sum { |pos| (pos.current_price || 0) * (pos.quantity || 0) }

      # Update equity to ensure it's current
      portfolio.update_equity! if portfolio.respond_to?(:update_equity!)
      portfolio.reload

      {
        available_balance: portfolio.available_swing_capital || 0,
        total_equity: portfolio.total_equity || 0,
        capital: portfolio.total_equity || 0,
        reserved_capital: portfolio.total_swing_exposure || 0,
        unrealized_pnl: portfolio.unrealized_pnl || 0,
        realized_pnl: portfolio.realized_pnl || 0,
        total_exposure: calculated_exposure,
        utilization_pct: portfolio.swing_capital.positive? ? (calculated_exposure / portfolio.swing_capital * 100).round(2) : 0,
        type: "paper",
      }
    else
      # Get live balance from DhanHQ API
      balance_result = Dhan::Balance.check_available_balance

      available_balance = balance_result[:success] ? balance_result[:balance] : 0

      # Calculate total equity from portfolio if available
      portfolio = Portfolio.live.recent.first
      total_equity = if portfolio
                       portfolio.total_equity || available_balance
                     else
                       available_balance
                     end

      # Calculate exposure from open positions
      open_positions = Position.live.open
      total_exposure = open_positions.sum { |pos| (pos.current_price || 0) * (pos.quantity || 0) }
      unrealized_pnl = open_positions.sum { |pos| pos.unrealized_pnl || 0 }

      {
        available_balance: available_balance,
        total_equity: total_equity,
        capital: total_equity - unrealized_pnl,
        reserved_capital: total_exposure,
        unrealized_pnl: unrealized_pnl,
        realized_pnl: portfolio&.realized_pnl || 0,
        total_exposure: total_exposure,
        utilization_pct: total_equity.positive? ? (total_exposure / total_equity * 100).round(2) : 0,
        type: "live",
        api_success: balance_result[:success],
        api_error: balance_result[:error],
      }
    end
  rescue StandardError => e
    Rails.logger.error("[BalanceHelper] Failed to get balance info: #{e.message}")
    {
      available_balance: 0,
      total_equity: 0,
      capital: 0,
      reserved_capital: 0,
      unrealized_pnl: 0,
      realized_pnl: 0,
      total_exposure: 0,
      utilization_pct: 0,
      type: mode,
      error: e.message,
    }
  end
end
