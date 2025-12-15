# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    mode = current_trading_mode

    if mode == "paper"
      @positions = Position.paper.open.includes(:instrument).order(opened_at: :desc).limit(20)
      @portfolio = CapitalAllocationPortfolio.paper.active.first
      # Ensure portfolio is initialized with balance
      if @portfolio.nil? || @portfolio.total_equity.zero?
        initializer_result = Portfolios::PaperPortfolioInitializer.call
        @portfolio = initializer_result[:portfolio] if initializer_result[:success]
      end
    else
      @positions = Position.live.open.includes(:instrument).order(opened_at: :desc).limit(20)
      @portfolio = Portfolio.live.recent.first
    end

    # Show both for comparison, but filter signals/orders by mode
    @live_positions = Position.live.open.includes(:instrument).order(opened_at: :desc).limit(20)
    @paper_positions = Position.paper.open.includes(:instrument).order(opened_at: :desc).limit(20)

    @recent_signals = if mode == "paper"
                        TradingSignal.paper.recent.includes(:instrument).limit(10)
                      else
                        TradingSignal.live.recent.includes(:instrument).limit(10)
                      end

    @pending_orders = Order.pending_approval.includes(:instrument).order(created_at: :desc)
    @recent_orders = Order.recent.includes(:instrument).limit(10)

    # Portfolio metrics
    @live_portfolio = Portfolio.live.recent.first
    @paper_portfolio = CapitalAllocationPortfolio.paper.active.first
    # Ensure paper portfolio is initialized with balance
    if mode == "paper" && (@paper_portfolio.nil? || @paper_portfolio.total_equity.zero?)
      initializer_result = Portfolios::PaperPortfolioInitializer.call
      @paper_portfolio = initializer_result[:portfolio] if initializer_result[:success]
    end

    # Get balance/wallet information
    @balance_info = get_balance_info(mode)

    # Calculate dashboard stats
    @stats = calculate_dashboard_stats
  end

  def toggle_trading_mode
    current_mode = session[:trading_mode] || "live"
    new_mode = current_mode == "live" ? "paper" : "live"
    session[:trading_mode] = new_mode

    Rails.logger.info("[DashboardController] Trading mode toggled: #{current_mode} -> #{new_mode}")

    respond_to do |format|
      format.json { render json: { mode: new_mode, message: "Switched to #{new_mode.upcase} mode" } }
      format.html { redirect_to request.referer || dashboard_path }
    end
  end

  def positions
    # Use session mode if no explicit mode param, but allow override
    @mode = params[:mode] || current_trading_mode
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

  def ai_evaluations
    # Show signals with AI evaluation data
    @mode = params[:mode] || current_trading_mode
    @status = params[:status] || "all" # all, executed, pending, failed

    signals_scope = TradingSignal.includes(:instrument)

    # Filter by mode
    signals_scope = case @mode
                    when "live"
                      signals_scope.live
                    when "paper"
                      signals_scope.paper
                    else
                      signals_scope
                    end

    # Filter by status
    signals_scope = case @status
                    when "executed"
                      signals_scope.executed
                    when "pending"
                      signals_scope.pending_approval
                    when "failed"
                      signals_scope.failed
                    when "not_executed"
                      signals_scope.not_executed
                    else
                      signals_scope
                    end

    @signals = signals_scope.recent.limit(100)

    # Extract AI data from signal metadata
    @signals_with_ai = @signals.map do |signal|
      metadata = signal.signal_metadata_hash
      ai_data = metadata.dig("ai_evaluation") || metadata.dig("ai") || {}

      {
        signal: signal,
        ai_score: ai_data["ai_score"] || ai_data[:ai_score],
        ai_confidence: ai_data["ai_confidence"] || ai_data[:ai_confidence],
        ai_summary: ai_data["ai_summary"] || ai_data[:ai_summary],
        ai_risk: ai_data["ai_risk"] || ai_data[:ai_risk],
        timeframe_alignment: ai_data["timeframe_alignment"] || ai_data[:timeframe_alignment],
        entry_timing: ai_data["entry_timing"] || ai_data[:entry_timing],
        has_ai_data: ai_data.present?,
      }
    end

    # Filter to only show signals with AI data if requested
    return unless params[:ai_only] == "true"

    @signals_with_ai = @signals_with_ai.select { |s| s[:has_ai_data] }
  end

  def signals
    @status = params[:status] || "all" # all, executed, pending, failed
    # Use session mode if no explicit type param
    @type = params[:type] || current_trading_mode

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
    # Note: Orders don't have live/paper distinction in the same way, but we can filter by mode if needed

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
    @limit = params[:limit]&.to_i # No default - show all if not specified
    @candidates = []
    @running = false

    # Read from database (persisted results)
    latest_results = ScreenerResult.latest_for(screener_type: "swing", limit: @limit)
    @candidates = latest_results.map(&:to_candidate_hash)
    @last_run = latest_results.first&.analyzed_at

    # Fallback to cache if no database results (backward compatibility)
    if @candidates.empty?
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
    end

    # Fetch real-time LTPs for all candidates (bulk API call)
    enrich_candidates_with_ltps(@candidates)

    # Categorize candidates
    categorize_candidates(@candidates, "swing")
  end

  def longterm_screener
    @limit = params[:limit].presence&.to_i # nil = show all
    @candidates = []
    @running = false

    # Read from database (persisted results)
    latest_results = ScreenerResult.latest_for(screener_type: "longterm", limit: @limit)
    @candidates = latest_results.map(&:to_candidate_hash)
    @last_run = latest_results.first&.analyzed_at

    # Fallback to cache if no database results (backward compatibility)
    if @candidates.empty?
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
    end

    # Fetch real-time LTPs for all candidates (bulk API call)
    enrich_candidates_with_ltps(@candidates)

    # Categorize candidates
    categorize_candidates(@candidates, "longterm")
  end

  def run_swing_screener
    limit = params[:limit].presence&.to_i # nil = full universe
    priority = params[:priority] || "normal" # "now" for high priority, "normal" for default

    # CRITICAL: Always use perform_later - NEVER use perform_now or sync execution
    # Jobs MUST run in worker process, not web process
    queue_name = priority == "now" ? :screener_now : :screener

    # Enqueue job with appropriate queue priority
    job = Screeners::SwingScreenerJob.set(queue: queue_name).perform_later(limit: limit)

    # Log job enqueueing with PID to verify process separation
    Rails.logger.info(
      "[DashboardController] Enqueued SwingScreenerJob: #{job.job_id} " \
      "queue=#{queue_name} web_pid=#{Process.pid}",
    )

    # Check if worker is running by checking queue status
    queue_status = check_solid_queue_status

    Rails.logger.info("[DashboardController] Queue status: #{queue_status.inspect}")

    message = if queue_status[:worker_running]
                priority_text = priority == "now" ? " (high priority)" : ""
                "Swing screener job queued#{priority_text} (Job ID: #{job.job_id}). Results will appear shortly."
              else
                "Job queued but SolidQueue worker may not be running! " \
                  "Please start it with: bin/rails solid_queue:start"
              end

    render json: {
      status: "queued",
      message: message,
      job_id: job.job_id,
      queue_status: queue_status,
      queue: queue_name.to_s,
    }
  rescue StandardError => e
    Rails.logger.error("[DashboardController] Failed to enqueue SwingScreenerJob: #{e.message}")
    render json: { status: "error", message: e.message }, status: :unprocessable_content
  end

  def run_longterm_screener
    limit = params[:limit].presence&.to_i # nil = full universe
    priority = params[:priority] || "normal" # "now" for high priority, "normal" for default

    # CRITICAL: Always use perform_later - NEVER use perform_now or sync execution
    # Jobs MUST run in worker process, not web process
    queue_name = priority == "now" ? :screener_now : :screener

    # Enqueue job with appropriate queue priority
    job = Screeners::LongtermScreenerJob.set(queue: queue_name).perform_later(limit: limit)

    # Log job enqueueing with PID to verify process separation
    Rails.logger.info(
      "[DashboardController] Enqueued LongtermScreenerJob: #{job.job_id} " \
      "queue=#{queue_name} web_pid=#{Process.pid}",
    )

    # Check if worker is running
    queue_status = check_solid_queue_status

    Rails.logger.info("[DashboardController] Queue status: #{queue_status.inspect}")

    message = if queue_status[:worker_running]
                priority_text = priority == "now" ? " (high priority)" : ""
                "Long-term screener job queued#{priority_text} (Job ID: #{job.job_id}). Results will appear shortly."
              else
                "Job queued but SolidQueue worker may not be running! " \
                  "Please start it with: bin/rails solid_queue:start"
              end

    render json: {
      status: "queued",
      message: message,
      job_id: job.job_id,
      queue_status: queue_status,
      queue: queue_name.to_s,
    }
  rescue StandardError => e
    Rails.logger.error("[DashboardController] Failed to enqueue LongtermScreenerJob: #{e.message}")
    render json: { status: "error", message: e.message }, status: :unprocessable_content
  end

  def check_screener_results
    screener_type = params[:type] || "swing"

    # Read from database first (persisted results)
    latest_results = ScreenerResult.latest_for(screener_type: screener_type, limit: nil)
    candidates = latest_results.map(&:to_candidate_hash)
    last_run = latest_results.first&.analyzed_at

    # Fallback to cache if no database results (backward compatibility)
    if candidates.empty?
      cache_key = "#{screener_type}_screener_results_#{Date.current}"
      candidates = Rails.cache.read(cache_key) || []
      last_run = Rails.cache.read("#{cache_key}_timestamp")
    end

    # Get progress information
    progress_key = "#{screener_type}_screener_progress_#{Date.current}"
    progress = Rails.cache.read(progress_key) || {}

    # Check if job is still running
    job_status = check_screener_job_status(screener_type)

    # Determine if we have partial or final results
    is_complete = progress[:status] == "completed" || (candidates.any? && last_run && last_run > 5.minutes.ago)
    has_partial = candidates.any? && progress[:status] == "running"

    render json: {
      ready: candidates.any?,
      candidate_count: candidates.size,
      last_run: last_run&.iso8601,
      message: if is_complete
                 "Results ready (#{candidates.size} candidates)"
               elsif has_partial
                 "Partial results available (#{candidates.size} candidates so far, still processing...)"
               else
                 "Still processing..."
               end,
      job_status: job_status,
      progress: progress,
      is_complete: is_complete,
      has_partial: has_partial,
      candidates: candidates.first(20), # Include top 20 candidates for progressive display
      source: latest_results.any? ? "database" : "cache", # Indicate data source
    }
  end

  def refresh_ltps
    screener_type = params[:type] || "swing"
    instrument_ids = params[:instrument_ids]&.split(",")&.map(&:to_i) || []

    return render json: { error: "No instrument IDs provided" }, status: :bad_request if instrument_ids.empty?

    # Load instrument records directly (more efficient than loading candidates)
    instruments = Instrument.where(id: instrument_ids).includes(:exchange)
    return render json: { error: "No instruments found" }, status: :not_found if instruments.empty?

    # Create candidate-like hashes for bulk fetcher
    candidates = instruments.map do |instrument|
      { instrument_id: instrument.id, symbol: instrument.symbol_name }
    end

    # Fetch real-time LTPs using bulk fetcher
    ltp_map = MarketData::BulkLtpFetcher.call(instruments: candidates)

    # Convert instrument IDs to strings for JavaScript compatibility
    ltp_map_string_keys = ltp_map.transform_keys(&:to_s)

    render json: { ltps: ltp_map_string_keys, updated_at: Time.current.iso8601 }
  rescue StandardError => e
    Rails.logger.error("[DashboardController] Failed to refresh LTPs: #{e.message}")
    Rails.logger.error("[DashboardController] Backtrace: #{e.backtrace.first(5).join("\n")}")
    render json: { error: e.message }, status: :internal_server_error
  end

  def check_screener_job_status(screener_type)
    return { running: false } unless solid_queue_installed?

    job_class = screener_type == "swing" ? "Screeners::SwingScreenerJob" : "Screeners::LongtermScreenerJob"

    # Find the most recent job of this type
    recent_job = SolidQueue::Job
                 .where("class_name LIKE ?", "%#{job_class.split('::').last}%")
                 .order(created_at: :desc)
                 .first

    return { running: false } unless recent_job

    {
      running: recent_job.finished_at.nil?,
      created_at: recent_job.created_at&.iso8601,
      finished_at: recent_job.finished_at&.iso8601,
      job_id: recent_job.id,
    }
  rescue StandardError => e
    Rails.logger.error("Error checking job status: #{e.message}")
    { running: false, error: e.message }
  end

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
        Rails.logger.error("[DashboardController] Failed to initialize paper portfolio: #{initializer_result[:error]}")
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
        Rails.logger.info("[DashboardController] Swing capital is zero, triggering rebalance...")
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
    Rails.logger.error("[DashboardController] Failed to get balance info: #{e.message}")
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
      dhan_api: check_dhan_api_status,
      telegram: check_telegram_status,
      queue: check_queue_health,
    }
  end

  def check_database_connection
    ActiveRecord::Base.connection.execute("SELECT 1")
    "Healthy"
  rescue StandardError => e
    "Error: #{e.message}"
  end

  def check_dhan_api_status
    require "dhan_hq"
    profile = DhanHQ::Models::Profile.fetch
    if profile&.dhan_client_id.present?
      "Healthy (Client ID: #{profile.dhan_client_id})"
    else
      "Connected but no client ID"
    end
  rescue LoadError
    "DhanHQ gem not installed"
  rescue StandardError => e
    "Error: #{e.message}"
  end

  def get_dhan_profile
    require "dhan_hq"
    profile = DhanHQ::Models::Profile.fetch
    return { error: "No profile data returned" } unless profile

    {
      client_id: profile.respond_to?(:dhan_client_id) ? profile.dhan_client_id : nil,
      token_validity: profile.respond_to?(:token_validity) ? profile.token_validity : nil,
      active_segment: profile.respond_to?(:active_segment) ? profile.active_segment : nil,
      ddpi: profile.respond_to?(:ddpi) ? profile.ddpi : nil,
      mtf: profile.respond_to?(:mtf) ? profile.mtf : nil,
      data_plan: profile.respond_to?(:data_plan) ? profile.data_plan : nil,
      data_validity: profile.respond_to?(:data_validity) ? profile.data_validity : nil,
    }
  rescue LoadError => e
    Rails.logger.error("[DashboardController] DhanHQ gem not installed: #{e.message}")
    { error: "DhanHQ gem not installed" }
  rescue StandardError => e
    Rails.logger.error("[DashboardController] Error fetching DhanHQ profile: #{e.message}")
    Rails.logger.error("[DashboardController] Backtrace: #{e.backtrace.first(10).join("\n")}")
    { error: e.message }
  end

  def check_dhan_expirations
    profile = get_dhan_profile
    return [] if profile.nil? || profile[:error]

    warnings = []
    now = Time.current

    # Check token validity (tokens are always valid for 24 hours)
    if profile[:token_validity]
      token_expiry = parse_dhan_date(profile[:token_validity])
      if token_expiry
        if token_expiry < now
          warnings << { type: "token", message: "Token EXPIRED on #{profile[:token_validity]}", severity: "critical" }
        else
          hours_until_expiry = ((token_expiry - now) / 1.hour).to_f.round(1)
          if hours_until_expiry <= 2
            warnings << { type: "token",
                          message: "Token expires in #{hours_until_expiry} hours (#{profile[:token_validity]})", severity: "critical" }
          elsif hours_until_expiry <= 6
            warnings << { type: "token",
                          message: "Token expires in #{hours_until_expiry} hours (#{profile[:token_validity]})", severity: "warning" }
          end
        end
      end
    end

    # Check data validity
    if profile[:data_validity]
      data_expiry = parse_dhan_date(profile[:data_validity])
      if data_expiry
        if data_expiry < now
          warnings << { type: "data_plan", message: "Data plan EXPIRED on #{profile[:data_validity]}",
                        severity: "critical" }
        else
          days_until_expiry = ((data_expiry - now) / 1.day).to_i
          if days_until_expiry <= 7
            warnings << { type: "data_plan",
                          message: "Data plan expires in #{days_until_expiry} days (#{profile[:data_validity]})", severity: "warning" }
          end
        end
      end
    end

    warnings
  rescue StandardError => e
    Rails.logger.error("[DashboardController] Error checking DhanHQ expirations: #{e.message}")
    []
  end

  def parse_dhan_date(date_string)
    return nil unless date_string.present?

    # Try parsing formats like "14/12/2025 19:08" or "2025-12-26 00:00:00.0"
    if date_string.match?(%r{\d{2}/\d{2}/\d{4}})
      # Format: "14/12/2025 19:08"
      parts = date_string.split
      date_part = parts[0]
      time_part = parts[1] || "00:00"
      day, month, year = date_part.split("/").map(&:to_i)
      hour, minute = time_part.split(":").map(&:to_i)
      Time.zone.local(year, month, day, hour, minute)
    elsif date_string.match?(/\d{4}-\d{2}-\d{2}/)
      # Format: "2025-12-26 00:00:00.0"
      Time.zone.parse(date_string)
    else
      nil
    end
  rescue StandardError
    nil
  end

  def about
    @dhan_profile = get_dhan_profile || { error: "Unable to fetch profile" }
    @dhan_expirations = check_dhan_expirations
    @telegram_status = get_telegram_info || { configured: false }
  end

  def get_telegram_info
    return { configured: false } unless TelegramNotifier.enabled?

    bot_token = ENV.fetch("TELEGRAM_BOT_TOKEN", nil)
    return { configured: false } unless bot_token.present?

    begin
      require "net/http"
      require "uri"
      uri = URI("https://api.telegram.org/bot#{bot_token}/getMe")
      response = Net::HTTP.get_response(uri)
      if response.code == "200"
        data = JSON.parse(response.body)
        if data["ok"]
          result = data["result"]
          {
            configured: true,
            bot_id: result["id"],
            bot_username: result["username"],
            bot_first_name: result["first_name"],
            bot_is_bot: result["is_bot"],
          }
        else
          { configured: true, error: data["description"] }
        end
      else
        { configured: true, error: "HTTP #{response.code}" }
      end
    rescue JSON::ParserError => e
      { configured: true, error: "Error parsing response: #{e.message}" }
    rescue StandardError => e
      { configured: true, error: e.message }
    end
  end

  def check_telegram_status
    # Check if Telegram is configured
    return "Not configured (missing bot token or chat ID)" unless TelegramNotifier.enabled?

    # Try a simple API call to verify connectivity
    # Using getMe endpoint which doesn't send a message
    bot_token = ENV.fetch("TELEGRAM_BOT_TOKEN", nil)
    return "Not configured" unless bot_token.present?

    begin
      require "net/http"
      require "uri"
      uri = URI("https://api.telegram.org/bot#{bot_token}/getMe")
      response = Net::HTTP.get_response(uri)
      if response.code == "200"
        data = JSON.parse(response.body)
        if data["ok"]
          bot_username = data.dig("result", "username")
          "Healthy#{" (@#{bot_username})" if bot_username}"
        else
          "API Error: #{data['description']}"
        end
      else
        "HTTP Error: #{response.code}"
      end
    rescue JSON::ParserError => e
      "Error parsing response: #{e.message}"
    rescue StandardError => e
      "Error: #{e.message}"
    end
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

      # Use actionable recommendation from screener if available, otherwise generate generic one
      recommendation = candidate[:recommendation].presence || generate_recommendation(candidate, indicators, score,
                                                                                      is_bullish, screener_type)

      candidate_with_rec = candidate.merge(recommendation: recommendation)

      if is_bullish
        @bullish_stocks << candidate_with_rec
      else
        @bearish_stocks << candidate_with_rec
      end

      # Add to recommendations if:
      # 1. Has actionable BUY/ACCUMULATE recommendation (from trade plan/accumulation plan), OR
      # 2. Setup status is READY or ACCUMULATE (tradeable), OR
      # 3. Generic "Buy" or "Strong Buy" recommendation
      is_actionable = candidate[:setup_status] == "READY" ||
                      candidate[:setup_status] == "ACCUMULATE" ||
                      candidate[:trade_plan].present? ||
                      candidate[:accumulation_plan].present? ||
                      /(BUY|ACCUMULATE|Strong Buy|Buy)/i.match?(recommendation)
      @recommendations << candidate_with_rec if is_actionable
    end

    # Sort recommendations by setup status (READY/ACCUMULATE first), then by score
    # Sort others by score
    @bullish_stocks.sort_by! { |c| [-(c[:score] || 0)] }
    @bearish_stocks.sort_by! { |c| [-(c[:score] || 0)] }
    @recommendations.sort_by! do |c|
      setup_priority = case c[:setup_status]
                       when "READY", "ACCUMULATE" then 0
                       when "WAIT_PULLBACK", "WAIT_BREAKOUT", "WAIT_DIP" then 1
                       when "IN_POSITION" then 2
                       else 3
                       end
      [setup_priority, -(c[:score] || 0)]
    end
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

  # Enriches candidates with real-time LTPs using bulk API call
  def enrich_candidates_with_ltps(candidates)
    return if candidates.empty?

    # Fetch LTPs for all candidates in bulk
    ltp_map = MarketData::BulkLtpFetcher.call(instruments: candidates)

    # Update candidates with real-time LTPs
    candidates.each do |candidate|
      instrument_id = candidate[:instrument_id]
      next unless instrument_id

      ltp = ltp_map[instrument_id]
      next unless ltp

      # Update indicators with real-time LTP
      # For swing screener: update daily_indicators
      # For longterm screener: update both daily and weekly indicators
      if candidate[:daily_indicators]
        candidate[:daily_indicators][:latest_close] = ltp
        candidate[:daily_indicators][:ltp] = ltp
      else
        candidate[:daily_indicators] = { latest_close: ltp, ltp: ltp }
      end

      # Also update top-level indicators for backward compatibility
      if candidate[:indicators]
        candidate[:indicators][:latest_close] = ltp
        candidate[:indicators][:ltp] = ltp
      else
        candidate[:indicators] = { latest_close: ltp, ltp: ltp }
      end

      # For longterm, also update weekly indicators
      if candidate[:weekly_indicators]
        candidate[:weekly_indicators][:latest_close] = ltp
        candidate[:weekly_indicators][:ltp] = ltp
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[DashboardController] Failed to enrich candidates with LTPs: #{e.message}")
    # Continue without LTP enrichment - fallback to cached prices
  end
end
