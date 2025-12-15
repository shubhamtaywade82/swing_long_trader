# frozen_string_literal: true

class PortfoliosController < ApplicationController
  def show
    # Use session mode if no explicit mode param
    @mode = params[:mode] || current_trading_mode

    if @mode == "paper"
      # Use CapitalAllocationPortfolio for paper trading (consistent with dashboard)
      @portfolio = CapitalAllocationPortfolio.paper.active.first
      # Ensure portfolio is initialized
      if @portfolio.nil? || @portfolio.total_equity.zero?
        initializer_result = Portfolios::PaperPortfolioInitializer.call
        @portfolio = initializer_result[:portfolio] if initializer_result[:success]
      end
      # Use unified Position model for paper positions
      @positions = Position.paper.open.includes(:instrument).order(opened_at: :desc)
      @ledger_entries = @portfolio&.ledger_entries&.order(created_at: :desc)&.limit(50) || []
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
      portfolio = CapitalAllocationPortfolio.paper.active.first
      return {} unless portfolio

      {
        total_equity: portfolio.total_equity || 0,
        capital: portfolio.total_equity || 0,
        unrealized_pnl: portfolio.unrealized_pnl || 0,
        realized_pnl: portfolio.realized_pnl || 0,
        max_drawdown: portfolio.max_drawdown || 0,
        utilization_pct: portfolio.swing_capital.positive? ? (portfolio.total_swing_exposure / portfolio.swing_capital * 100).round(2) : 0,
        open_positions_count: Position.paper.open.count,
        closed_positions_count: Position.paper.closed.count,
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
