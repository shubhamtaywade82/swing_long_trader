# frozen_string_literal: true

class PortfoliosController < ApplicationController
  include PortfolioInitializer

  # @api public
  # Displays portfolio information and performance metrics
  # @param [String] mode Trading mode: "live" or "paper"
  # @return [void] Renders portfolios/show view
  def show
    portfolio_params = params.permit(:mode)
    @mode = validate_trading_mode(portfolio_params[:mode])

    if @mode == "paper"
      # Use CapitalAllocationPortfolio for paper trading (consistent with dashboard)
      @portfolio = CapitalAllocationPortfolio.paper.active.first
      ensure_paper_portfolio_initialized
      # Use unified Position model for paper positions
      @positions = Position.paper.open.includes(:instrument).order(opened_at: :desc).limit(100)
      @ledger_entries = @portfolio ? @portfolio.ledger_entries.order(created_at: :desc).limit(50) : []
    else
      @portfolios = Portfolio.live.recent.limit(30)
      @current_portfolio = @portfolios.first
      @positions = @current_portfolio ? @current_portfolio.positions.includes(:instrument).order(opened_at: :desc).limit(100) : []
    end

    @performance_metrics = calculate_performance_metrics(@mode)
  end

  private

  def validate_trading_mode(mode_param)
    %w[live paper].include?(mode_param.to_s) ? mode_param.to_s : current_trading_mode
  end

  # @api private
  # Calculates performance metrics for the portfolio
  # @param [String] mode Trading mode: "live" or "paper"
  # @return [Hash] Performance metrics hash
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
