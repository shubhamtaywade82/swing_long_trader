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

    # Also check previous days for last run
    if @candidates.empty? && @last_run.nil?
      (1..7).each do |days_ago|
        prev_key = "swing_screener_results_#{Date.current - days_ago.days}"
        prev_candidates = Rails.cache.read(prev_key)
        next unless prev_candidates&.any?

        @candidates = prev_candidates
        @last_run = Rails.cache.read("#{prev_key}_timestamp")
        break
      end
    end

    # Categorize candidates
    categorize_candidates(@candidates, "swing")
  end

  def longterm_screener
    @limit = params[:limit]&.to_i || 10
    @candidates = []
    @running = false

    # Check if there's a recent run stored in session or cache
    cache_key = "longterm_screener_results_#{Date.current}"
    @candidates = Rails.cache.read(cache_key) || []
    @last_run = Rails.cache.read("#{cache_key}_timestamp")

    # Also check previous days for last run
    if @candidates.empty? && @last_run.nil?
      (1..7).each do |days_ago|
        prev_key = "longterm_screener_results_#{Date.current - days_ago.days}"
        prev_candidates = Rails.cache.read(prev_key)
        next unless prev_candidates&.any?

        @candidates = prev_candidates
        @last_run = Rails.cache.read("#{prev_key}_timestamp")
        break
      end
    end

    # Categorize candidates
    categorize_candidates(@candidates, "longterm")
  end

  def run_swing_screener
    limit = params[:limit]&.to_i || 50
    sync = params[:sync] == "true"

    if sync
      # Run synchronously for testing (bypasses queue)
      begin
        candidates = Screeners::SwingScreener.call(limit: limit)

        # Cache results
        cache_key = "swing_screener_results_#{Date.current}"
        Rails.cache.write(cache_key, candidates, expires_in: 24.hours)
        Rails.cache.write("#{cache_key}_timestamp", Time.current, expires_in: 24.hours)

        render json: {
          status: "completed",
          message: "Swing screener completed. Found #{candidates.size} candidates.",
          candidate_count: candidates.size,
        }
      rescue StandardError => e
        render json: { status: "error", message: e.message }, status: :unprocessable_content
      end
    else
      # Run screener in background
      job = Screeners::SwingScreenerJob.perform_later(limit: limit)

      # Log job enqueueing
      Rails.logger.info("[DashboardController] Enqueued SwingScreenerJob: #{job.job_id}")

      # Check if worker is running by checking queue status
      queue_status = check_solid_queue_status

      Rails.logger.info("[DashboardController] Queue status: #{queue_status.inspect}")

      message = if queue_status[:worker_running]
                  "Swing screener job queued (Job ID: #{job.job_id}). Results will appear shortly."
                else
                  "Job queued but SolidQueue worker may not be running! " \
                    "Please start it with: bin/rails solid_queue:start"
                end

      render json: {
        status: "queued",
        message: message,
        job_id: job.job_id,
        queue_status: queue_status,
      }
    end
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :unprocessable_content
  end

  def run_longterm_screener
    limit = params[:limit]&.to_i || 10
    sync = params[:sync] == "true"

    if sync
      # Run synchronously for testing (bypasses queue)
      begin
        candidates = Screeners::LongtermScreener.call(limit: limit)

        # Cache results
        cache_key = "longterm_screener_results_#{Date.current}"
        Rails.cache.write(cache_key, candidates, expires_in: 24.hours)
        Rails.cache.write("#{cache_key}_timestamp", Time.current, expires_in: 24.hours)

        render json: {
          status: "completed",
          message: "Long-term screener completed. Found #{candidates.size} candidates.",
          candidate_count: candidates.size,
        }
      rescue StandardError => e
        render json: { status: "error", message: e.message }, status: :unprocessable_content
      end
    else
      # Run screener in background
      job = Screeners::LongtermScreenerJob.perform_later(limit: limit)

      # Log job enqueueing
      Rails.logger.info("[DashboardController] Enqueued LongtermScreenerJob: #{job.job_id}")

      # Check if worker is running
      queue_status = check_solid_queue_status

      Rails.logger.info("[DashboardController] Queue status: #{queue_status.inspect}")

      message = if queue_status[:worker_running]
                  "Long-term screener job queued (Job ID: #{job.job_id}). Results will appear shortly."
                else
                  "Job queued but SolidQueue worker may not be running! " \
                    "Please start it with: bin/rails solid_queue:start"
                end

      render json: {
        status: "queued",
        message: message,
        job_id: job.job_id,
        queue_status: queue_status,
      }
    end
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :unprocessable_content
  end

  def check_screener_results
    screener_type = params[:type] || "swing"
    cache_key = "#{screener_type}_screener_results_#{Date.current}"
    candidates = Rails.cache.read(cache_key) || []
    last_run = Rails.cache.read("#{cache_key}_timestamp")

    render json: {
      ready: candidates.any?,
      candidate_count: candidates.size,
      last_run: last_run&.iso8601,
      message: candidates.any? ? "Results ready" : "Still processing...",
    }
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
    return "Not installed" unless solid_queue_installed?

    stats = get_solid_queue_stats
    if stats[:pending] > 100 || stats[:failed] > 50
      "Warning: #{stats[:pending]} pending, #{stats[:failed]} failed"
    elsif !stats[:worker_running]
      "Worker not running"
    else
      "Healthy"
    end
  rescue StandardError => e
    "Error: #{e.message}"
  end

  def get_queue_stats
    return { pending: 0, running: 0, failed: 0 } unless solid_queue_installed?

    get_solid_queue_stats
  end

  def check_solid_queue_status
    return { worker_running: false, pending: 0, running: 0, failed: 0 } unless solid_queue_installed?

    stats = get_solid_queue_stats

    # Check if worker is running by looking for recent activity
    # If there are running jobs or jobs finished recently, worker is likely running
    recent_activity = SolidQueue::Job
                      .where("finished_at > ?", 5.minutes.ago)
                      .exists?

    # Also check if there are claimed executions (jobs being processed)
    has_claimed = SolidQueue::ClaimedExecution.exists?

    {
      worker_running: recent_activity || has_claimed || stats[:running] > 0,
      pending: stats[:pending],
      running: stats[:running],
      failed: stats[:failed],
      recent_activity: recent_activity,
    }
  rescue StandardError => e
    Rails.logger.error("Error checking SolidQueue status: #{e.message}")
    { worker_running: false, pending: 0, running: 0, failed: 0, error: e.message }
  end

  def get_solid_queue_stats
    return { pending: 0, running: 0, failed: 0 } unless solid_queue_installed?

    {
      pending: SolidQueue::Job.where(finished_at: nil)
                              .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
                              .count,
      running: SolidQueue::ClaimedExecution.count,
      failed: SolidQueue::FailedExecution.count,
    }
  rescue StandardError => e
    Rails.logger.error("Error getting SolidQueue stats: #{e.message}")
    { pending: 0, running: 0, failed: 0 }
  end

  def solid_queue_installed?
    defined?(SolidQueue) && ActiveRecord::Base.connection.table_exists?("solid_queue_jobs")
  end

  def get_recent_errors
    # Would query error logs or error tracking system
    []
  end

  def categorize_candidates(candidates, screener_type)
    return if candidates.empty?

    # Get symbols that have open positions
    candidate_symbols = candidates.map { |c| c[:symbol] }
    open_positions = Position.open.where(symbol: candidate_symbols)
    paper_positions = PaperPosition.open.where(instrument_id: Instrument.where(symbol_name: candidate_symbols).pluck(:id))

    # Create position lookup
    @position_lookup = {}
    open_positions.each { |pos| @position_lookup[pos.symbol] = { mode: pos.live? ? "live" : "paper", position: pos } }
    paper_positions.each do |pos|
      symbol = pos.instrument&.symbol_name
      next unless symbol

      @position_lookup[symbol] ||= { mode: "paper", position: pos }
    end

    # Categorize candidates
    @bullish_stocks = []
    @bearish_stocks = []
    @flag_stocks = []
    @recommendations = []

    candidates.each do |candidate|
      symbol = candidate[:symbol]
      score = candidate[:score] || 0
      indicators = candidate[:indicators] || candidate[:daily_indicators] || {}

      # Check if already in position (Flag stock)
      if @position_lookup[symbol]
        position_info = @position_lookup[symbol]
        @flag_stocks << candidate.merge(
          position_mode: position_info[:mode],
          position: position_info[:position],
          recommendation: "Already in #{position_info[:mode].upcase} position",
        )
        next
      end

      # Determine if bullish or bearish
      is_bullish = determine_bullish(candidate, indicators, screener_type)

      # Generate recommendation
      recommendation = generate_recommendation(candidate, indicators, score, is_bullish, screener_type)

      candidate_with_rec = candidate.merge(recommendation: recommendation)

      if is_bullish
        @bullish_stocks << candidate_with_rec
      else
        @bearish_stocks << candidate_with_rec
      end

      # Add to recommendations if score is high
      @recommendations << candidate_with_rec if score >= 60
    end

    # Sort by score
    @bullish_stocks.sort_by! { |c| -(c[:score] || 0) }
    @bearish_stocks.sort_by! { |c| -(c[:score] || 0) }
    @recommendations.sort_by! { |c| -(c[:score] || 0) }
    @flag_stocks.sort_by! { |c| -(c[:score] || 0) }
  end

  def determine_bullish(candidate, indicators, screener_type)
    # Check supertrend
    st = indicators[:supertrend] || candidate.dig(:weekly_indicators, :supertrend)
    return false if st && st[:direction] == :bearish

    # Check EMA trend
    if screener_type == "longterm"
      weekly_ema20 = candidate.dig(:weekly_indicators, :ema20)
      weekly_ema50 = candidate.dig(:weekly_indicators, :ema50)
      return false if weekly_ema20 && weekly_ema50 && weekly_ema20 < weekly_ema50
    end

    ema20 = indicators[:ema20]
    ema50 = indicators[:ema50]
    return false if ema20 && ema50 && ema20 < ema50

    # Check RSI (not overbought)
    rsi = indicators[:rsi] || candidate.dig(:daily_indicators, :rsi)
    return false if rsi && rsi > 75

    # Check score
    score = candidate[:score] || 0
    score >= 50
  end

  def generate_recommendation(_candidate, _indicators, score, is_bullish, _screener_type)
    return "Avoid - Bearish signals" unless is_bullish

    if score >= 75
      "Strong Buy - High score with bullish indicators"
    elsif score >= 60
      "Buy - Good opportunity with strong signals"
    elsif score >= 50
      "Watch - Moderate signals, wait for confirmation"
    else
      "Wait - Weak signals, monitor for improvement"
    end
  end
end
