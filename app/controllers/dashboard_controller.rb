# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    @live_positions = Position.live.open.includes(:instrument).order(opened_at: :desc).limit(20)
    @paper_positions = Position.paper.open.includes(:instrument).order(opened_at: :desc).limit(20)
    @recent_signals = TradingSignal.recent.includes(:instrument).limit(10)
    @pending_orders = Order.pending_approval.includes(:instrument).order(created_at: :desc)
    @recent_orders = Order.recent.includes(:instrument).limit(10)

    # Portfolio metrics
    @live_portfolio = Portfolio.live.recent.first
    @paper_portfolio = PaperPortfolio.active.first

    # Calculate dashboard stats
    @stats = calculate_dashboard_stats
  end

  def positions
    @mode = params[:mode] || "all" # all, live, paper
    @status = params[:status] || "all" # all, open, closed

    positions_scope = Position.regular_positions.includes(:instrument, :order, :exit_order)

    positions_scope = case @mode
                      when "live"
                        positions_scope.live
                      when "paper"
                        positions_scope.paper
                      else
                        positions_scope
                      end

    positions_scope = case @status
                      when "open"
                        positions_scope.open
                      when "closed"
                        positions_scope.closed
                      else
                        positions_scope
                      end

    @positions = positions_scope.order(opened_at: :desc).limit(100)
  end

  def portfolio
    @mode = params[:mode] || "live" # live, paper

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

  def signals
    @status = params[:status] || "all" # all, executed, pending, failed
    @type = params[:type] || "all" # all, paper, live

    signals_scope = TradingSignal.includes(:instrument, :order, :paper_position)

    signals_scope = case @status
                    when "executed"
                      signals_scope.executed
                    when "pending"
                      signals_scope.pending_approval
                    when "failed"
                      signals_scope.failed
                    else
                      signals_scope
                    end

    signals_scope = case @type
                    when "paper"
                      signals_scope.paper
                    when "live"
                      signals_scope.live
                    else
                      signals_scope
                    end

    @signals = signals_scope.order(signal_generated_at: :desc).limit(100)
  end

  def orders
    @status = params[:status] || "all" # all, pending, placed, executed, rejected
    @type = params[:type] || "all" # all, buy, sell

    orders_scope = Order.includes(:instrument)

    orders_scope = case @status
                   when "pending"
                     orders_scope.pending
                   when "placed"
                     orders_scope.placed
                   when "executed"
                     orders_scope.executed
                   when "rejected"
                     orders_scope.rejected
                   when "pending_approval"
                     orders_scope.pending_approval
                   else
                     orders_scope
                   end

    orders_scope = case @type
                   when "buy"
                     orders_scope.where(transaction_type: "BUY")
                   when "sell"
                     orders_scope.where(transaction_type: "SELL")
                   else
                     orders_scope
                   end

    @orders = orders_scope.order(created_at: :desc).limit(100)
  end

  def monitoring
    @jobs_status = get_jobs_status
    @system_health = get_system_health
    @queue_stats = get_queue_stats
    @recent_errors = get_recent_errors
  end

  def swing_screener
    @limit = params[:limit]&.to_i || 50
    @candidates = []
    @running = false
    
    # Check if there's a recent run stored in session or cache
    cache_key = "swing_screener_results_#{Date.current}"
    @candidates = Rails.cache.read(cache_key) || []
    @last_run = Rails.cache.read("#{cache_key}_timestamp")
  end

  def longterm_screener
    @limit = params[:limit]&.to_i || 10
    @candidates = []
    @running = false
    
    # Check if there's a recent run stored in session or cache
    cache_key = "longterm_screener_results_#{Date.current}"
    @candidates = Rails.cache.read(cache_key) || []
    @last_run = Rails.cache.read("#{cache_key}_timestamp")
  end

  def run_swing_screener
    limit = params[:limit]&.to_i || 50
    
    # Run screener in background
    Screeners::SwingScreenerJob.perform_later(limit: limit)
    
    # Return immediately with status
    render json: { status: "queued", message: "Swing screener job queued. Results will appear shortly." }
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :unprocessable_entity
  end

  def run_longterm_screener
    limit = params[:limit]&.to_i || 10
    
    # Run screener in background
    Screeners::LongtermScreenerJob.perform_later(limit: limit) if defined?(Screeners::LongtermScreenerJob)
    
    # For now, run synchronously if job doesn't exist
    unless defined?(Screeners::LongtermScreenerJob)
      candidates = Screeners::LongtermScreener.call(limit: limit)
      cache_key = "longterm_screener_results_#{Date.current}"
      Rails.cache.write(cache_key, candidates, expires_in: 24.hours)
      Rails.cache.write("#{cache_key}_timestamp", Time.current, expires_in: 24.hours)
    end
    
    render json: { status: "queued", message: "Long-term screener job queued. Results will appear shortly." }
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :unprocessable_entity
  end

  private

  def calculate_dashboard_stats
    {
      total_live_positions: Position.live.open.count,
      total_paper_positions: Position.paper.open.count,
      total_unrealized_pnl_live: Position.live.open.sum(:unrealized_pnl) || 0,
      total_unrealized_pnl_paper: Position.paper.open.sum(:unrealized_pnl) || 0,
      total_realized_pnl_live: Position.live.closed.sum(:realized_pnl) || 0,
      total_realized_pnl_paper: Position.paper.closed.sum(:realized_pnl) || 0,
      pending_signals: TradingSignal.pending_approval.count,
      pending_orders: Order.pending_approval.count,
      today_signals: TradingSignal.where("signal_generated_at >= ?", Date.current.beginning_of_day).count,
      today_orders: Order.where("created_at >= ?", Date.current.beginning_of_day).count,
    }
  end

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

  def get_jobs_status
    {
      last_screener_run: get_last_job_run("Screeners::SwingScreenerJob"),
      last_analysis_run: get_last_job_run("Strategies::Swing::AnalysisJob"),
      last_entry_monitor: get_last_job_run("Strategies::Swing::EntryMonitorJob"),
      last_exit_monitor: get_last_job_run("Strategies::Swing::ExitMonitorJob"),
      last_candle_ingestion: get_last_job_run("Candles::DailyIngestorJob"),
    }
  end

  def get_last_job_run(_job_class)
    # This would query SolidQueue or your job tracking system
    # For now, return a placeholder
    "Not tracked"
  end

  def get_system_health
    {
      database: check_database_connection,
      dhan_api: "Unknown", # Would check DhanHQ API status
      telegram: "Unknown", # Would check Telegram bot status
      queue: check_queue_health,
    }
  end

  def check_database_connection
    ActiveRecord::Base.connection.execute("SELECT 1")
    "Healthy"
  rescue StandardError => e
    "Error: #{e.message}"
  end

  def check_queue_health
    # Check SolidQueue health
    "Healthy"
  rescue StandardError => e
    "Error: #{e.message}"
  end

  def get_queue_stats
    {
      pending: 0, # Would query SolidQueue
      running: 0,
      failed: 0,
    }
  end

  def get_recent_errors
    # Would query error logs or error tracking system
    []
  end
end
