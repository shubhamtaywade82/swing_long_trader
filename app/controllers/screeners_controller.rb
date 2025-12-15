# frozen_string_literal: true

class ScreenersController < ApplicationController
  include SolidQueueHelper

  before_action :set_screener_type, only: [:show, :run, :check_results]

  def swing
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

    # Categorize candidates
    categorize_candidates(@candidates, "swing")
  end

  def longterm
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

    # Categorize candidates
    categorize_candidates(@candidates, "longterm")
  end

  def run
    screener_type = @screener_type
    limit = params[:limit].presence&.to_i # nil = full universe
    priority = params[:priority] || "normal" # "now" for high priority, "normal" for default

    # CRITICAL: Always use perform_later - NEVER use perform_now or sync execution
    # Jobs MUST run in worker process, not web process
    queue_name = priority == "now" ? :screener_now : :screener

    # Enqueue job with appropriate queue priority
    job_class = screener_type == "swing" ? Screeners::SwingScreenerJob : Screeners::LongtermScreenerJob
    job = job_class.set(queue: queue_name).perform_later(limit: limit)

    # Log job enqueueing with PID to verify process separation
    Rails.logger.info(
      "[ScreenersController] Enqueued #{job_class.name}: #{job.job_id} " \
      "queue=#{queue_name} web_pid=#{Process.pid}",
    )

    # Check if worker is running by checking queue status
    queue_status = check_solid_queue_status

    Rails.logger.info("[ScreenersController] Queue status: #{queue_status.inspect}")

    message = if queue_status[:worker_running]
                priority_text = priority == "now" ? " (high priority)" : ""
                "#{screener_type.capitalize} screener job queued#{priority_text} (Job ID: #{job.job_id}). Results will appear shortly."
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
    Rails.logger.error("[ScreenersController] Failed to enqueue screener job: #{e.message}")
    render json: { status: "error", message: e.message }, status: :unprocessable_content
  end

  def check_results
    screener_type = @screener_type

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

  def start_ltp_updates
    screener_type = params[:screener_type] || "swing"
    instrument_ids = params[:instrument_ids]&.split(",")&.map(&:to_i)
    symbols = params[:symbols]&.split(",")
    use_websocket = params[:websocket] == "true" || ENV["DHANHQ_WS_ENABLED"] == "true"

    if use_websocket && websocket_available?
      # Check if WebSocket stream is already running
      stream_key = build_stream_key(screener_type, instrument_ids, symbols)
      if websocket_stream_running?(stream_key)
        render json: {
          status: "already_running",
          message: "WebSocket stream already active",
          mode: "websocket",
        }
        return
      end

      # Check if job is already queued/running
      existing_job = find_existing_websocket_job(screener_type, instrument_ids, symbols)
      if existing_job
        render json: {
          status: "queued",
          message: "WebSocket job already queued",
          job_id: existing_job.id,
          mode: "websocket",
        }
        return
      end

      # Use WebSocket for real-time tick streaming
      job = MarketHub::WebsocketTickStreamerJob.perform_later(
        screener_type: screener_type,
        instrument_ids: instrument_ids&.join(","),
        symbols: symbols&.join(","),
      )

      render json: {
        status: "started",
        message: "Real-time LTP updates started (WebSocket)",
        job_id: job.job_id,
        mode: "websocket",
      }
    else
      # Fallback to polling (5-second interval)
      job = MarketHub::LtpPollerJob.perform_later(
        screener_type: screener_type,
        instrument_ids: instrument_ids,
        symbols: symbols,
      )

      render json: {
        status: "started",
        message: "LTP updates started (polling every 5 seconds)",
        job_id: job.job_id,
        mode: "polling",
      }
    end
  rescue StandardError => e
    Rails.logger.error("[ScreenersController] Failed to start LTP updates: #{e.message}")
    render json: { status: "error", message: e.message }, status: :unprocessable_content
  end

  def stop_ltp_updates
    # Note: In a production system, you'd want to track active jobs and cancel them
    # For now, jobs will stop automatically when market closes
    render json: {
      status: "stopped",
      message: "LTP updates will stop when market closes",
    }
  end

  private

  def set_screener_type
    @screener_type = params[:type] || params[:screener_type] || "swing"
  end

  def websocket_available?
    Rails.application.config.x.dhanhq&.ws_enabled == true ||
      ENV["DHANHQ_WS_ENABLED"] == "true"
  end

  def build_stream_key(screener_type, instrument_ids, symbols)
    parts = []
    parts << "type:#{screener_type}" if screener_type
    parts << "ids:#{instrument_ids&.join(',')}" if instrument_ids&.any?
    parts << "symbols:#{symbols&.join(',')}" if symbols&.any?
    parts.any? ? parts.join("|") : "default"
  end

  def websocket_stream_running?(stream_key)
    # Check if stream is running using cross-process cache check
    return false unless defined?(MarketHub::WebsocketTickStreamerJob)

    cache_key = "websocket_stream:#{stream_key}"
    cache_data = Rails.cache.read(cache_key)
    return false unless cache_data

    # Check if stream is running and heartbeat is recent
    status = cache_data[:status] rescue nil
    return false unless status == "running"

    heartbeat = cache_data[:heartbeat] rescue nil
    return false unless heartbeat

    heartbeat_time = Time.parse(heartbeat) rescue nil
    return false unless heartbeat_time

    # Stream is running if heartbeat is within last 2 minutes
    Time.current - heartbeat_time < 2.minutes
  end

  def find_existing_websocket_job(screener_type, instrument_ids, symbols)
    return nil unless solid_queue_installed?

    # Find jobs for WebsocketTickStreamerJob that match this stream
    # We need to match by arguments since we can't easily query job arguments
    # So we check for recent jobs of this type

    # Check pending jobs (created in last 10 minutes)
    pending_job = SolidQueue::Job
                  .where("class_name LIKE ?", "%WebsocketTickStreamerJob%")
                  .where(finished_at: nil)
                  .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
                  .where("created_at > ?", 10.minutes.ago)
                  .order(created_at: :desc)
                  .first

    return pending_job if pending_job

    # Check running jobs (claimed executions)
    running_execution = SolidQueue::ClaimedExecution
                       .joins(:job)
                       .where("solid_queue_jobs.class_name LIKE ?", "%WebsocketTickStreamerJob%")
                       .where("solid_queue_jobs.finished_at IS NULL")
                       .where("solid_queue_jobs.created_at > ?", 10.minutes.ago)
                       .order("solid_queue_jobs.created_at DESC")
                       .first

    running_execution&.job
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
end
