# frozen_string_literal: true

class PortfoliosController < ApplicationController
  def show
    # Use session mode if no explicit mode param
    @mode = params[:mode] || current_trading_mode

    if @mode == "paper"
      @portfolio = PaperPortfolio.active.first
      @positions = @portfolio&.paper_positions&.order(created_at: :desc) || []
      @ledger_entries = @portfolio&.paper_ledgers&.order(created_at: :desc)&.limit(50) || []
    else
      @portfolios = Portfolio.live.recent.limit(30)
      @current_portfolio = @portfolios.first
      @positions = @current_portfolio&.positions&.includes(:instrument)&.order(opened_at: :desc) || []
    end

    @performance_metrics = calculate_performance_metrics(@mode)
  end

  private

  def calculate_performance_metrics(mode)
    if mode == "paper"
      portfolio = PaperPortfolio.active.first
      return {} unless portfolio

      {
        total_equity: portfolio.total_equity || 0,
        capital: portfolio.capital || 0,
        unrealized_pnl: portfolio.pnl_unrealized || 0,
        realized_pnl: portfolio.pnl_realized || 0,
        max_drawdown: portfolio.max_drawdown || 0,
        utilization_pct: portfolio.utilization_pct || 0,
        open_positions_count: portfolio.open_positions.count,
        closed_positions_count: portfolio.closed_positions.count,
      }
    else
      portfolio = Portfolio.live.recent.first
      return {} unless portfolio

      {
        total_equity: portfolio.total_equity || 0,
        opening_capital: portfolio.opening_capital || 0,
        closing_capital: portfolio.closing_capital || 0,
        open_positions_count: portfolio.open_positions_count || 0,
        closed_positions_count: portfolio.closed_positions_count || 0,
      }
    end
  end
end
