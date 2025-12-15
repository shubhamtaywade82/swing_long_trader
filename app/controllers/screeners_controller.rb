# frozen_string_literal: true

require "digest"

class ScreenersController < ApplicationController
  include SolidQueueHelper

  # Constants
  WEBSOCKET_HEARTBEAT_TIMEOUT = 2.minutes
  MAX_PENDING_JOBS_WARNING = 100
  MAX_FAILED_JOBS_WARNING = 50
  CACHE_FALLBACK_DAYS = 7
  WEBSOCKET_JOB_LOOKBACK_MINUTES = 10

  before_action :set_screener_type, only: [:run, :check_results]

  # @api public
  # Fetches and displays swing screener results
  # @param [Integer] limit Optional limit on number of results
  # @return [void] Renders swing_screener view
  def swing
    load_screener_results("swing")
  end

  # @api public
  # Fetches and displays longterm screener results
  # @param [Integer] limit Optional limit on number of results
  # @return [void] Renders longterm_screener view
  def longterm
    load_screener_results("longterm")
  end

  # @api public
  # Enqueues a screener job to run in the background
  # @param [String] type Screener type: "swing" or "longterm"
  # @param [Integer] limit Optional limit on number of instruments to screen
  # @param [String] priority Job priority: "now" (high) or "normal" (default)
  # @return [JSON] Job status and ID
  def run
    screener_params = params.permit(:type, :limit, :priority)
    screener_type = validate_screener_type(screener_params[:type] || @screener_type)
    limit = parse_limit(screener_params[:limit])
    priority = validate_priority(screener_params[:priority])

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
  end

  # @api public
  # Checks the status of screener job results
  # @param [String] type Screener type: "swing" or "longterm"
  # @return [JSON] Status of screener results
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
      message: build_status_message(is_complete, has_partial, candidates.size),
      job_status: job_status,
      progress: progress,
      is_complete: is_complete,
      has_partial: has_partial,
      candidates: candidates.first(20), # Include top 20 candidates for progressive display
      source: latest_results.any? ? "database" : "cache", # Indicate data source
    }
  end

  # @api public
  # Stops LTP updates (jobs will stop automatically when market closes)
  # @return [JSON] Status message
  def stop_ltp_updates
    render json: {
      status: "stopped",
      message: "LTP updates will stop when market closes",
    }
  end

  # @api public
  # Starts real-time LTP (Last Traded Price) updates for screener stocks
  # @param [String] screener_type Type of screener: "swing" or "longterm"
  # @param [String] instrument_ids Comma-separated list of instrument IDs
  # @param [String] symbols Comma-separated list of stock symbols
  # @param [String] websocket Whether to use WebSocket (true) or polling (false)
  # @return [JSON] Status of LTP update stream
  def start_ltp_updates
    ltp_params = params.permit(:screener_type, :instrument_ids, :symbols, :websocket)
    screener_type = validate_screener_type(ltp_params[:screener_type])
    instrument_ids = parse_instrument_ids(ltp_params[:instrument_ids])
    symbols = parse_symbols(ltp_params[:symbols])

    # Validate at least one identifier provided
    unless instrument_ids.any? || symbols.any?
      return render json: {
        error: "Must provide instrument_ids or symbols",
      }, status: :unprocessable_entity
    end

    use_websocket = ltp_params[:websocket] == "true" || ENV["DHANHQ_WS_ENABLED"] == "true"

    if use_websocket && websocket_available?
      stream_key = build_stream_key(screener_type, instrument_ids, symbols)

      # Use PostgreSQL advisory lock to prevent race condition
      lock_key = Digest::MD5.hexdigest("websocket_stream_#{stream_key}").to_i(16) % (2**31)

      # Try to acquire advisory lock (non-blocking)
      lock_result = ActiveRecord::Base.connection.execute(
        "SELECT pg_try_advisory_lock(#{lock_key}) AS acquired"
      )
      lock_acquired = lock_result.first["acquired"]

      unless lock_acquired
        return render json: {
          status: "already_running",
          message: "WebSocket stream is being started by another request",
          mode: "websocket",
        }
      end

      begin
        if websocket_stream_running?(stream_key)
          return render json: {
            status: "already_running",
            message: "WebSocket stream already active",
            mode: "websocket",
          }
        end

        # Check if job is already queued/running
        existing_job = find_existing_websocket_job(screener_type, instrument_ids, symbols)
        if existing_job
          return render json: {
            status: "queued",
            message: "WebSocket job already queued",
            job_id: existing_job.id,
            mode: "websocket",
          }
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
      ensure
        # Always release the lock
        ActiveRecord::Base.connection.execute("SELECT pg_advisory_unlock(#{lock_key})")
      end
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
  end

  private

  def build_status_message(is_complete, has_partial, candidate_count)
    if is_complete
      "Results ready (#{candidate_count} candidates)"
    elsif has_partial
      "Partial results available (#{candidate_count} candidates so far, still processing...)"
    else
      "Still processing..."
    end
  end

  # Loads screener results from database or cache
  # @param [String] screener_type Type of screener: "swing" or "longterm"
  def load_screener_results(screener_type)
    @limit = params[:limit].presence&.to_i
    @candidates = []
    @running = false

    # Read from database (persisted results)
    latest_results = ScreenerResult.latest_for(screener_type: screener_type, limit: @limit)
    @candidates = latest_results.map(&:to_candidate_hash)
    @last_run = latest_results.first&.analyzed_at

    # Fallback to cache if no database results (backward compatibility)
    if @candidates.empty?
      cache_key = "#{screener_type}_screener_results_#{Date.current}"
      @candidates = Rails.cache.read(cache_key) || []
      @last_run = Rails.cache.read("#{cache_key}_timestamp")

      # Also check previous days for last run
      if @candidates.empty? && @last_run.nil?
        (1..CACHE_FALLBACK_DAYS).each do |days_ago|
          prev_key = "#{screener_type}_screener_results_#{Date.current - days_ago.days}"
          prev_candidates = Rails.cache.read(prev_key)
          next unless prev_candidates&.any?

          @candidates = prev_candidates
          @last_run = Rails.cache.read("#{prev_key}_timestamp")
          break
        end
      end
    end

    # Categorize candidates
    categorize_candidates(@candidates, screener_type)
  end

  def set_screener_type
    @screener_type = validate_screener_type(params[:type] || params[:screener_type])
  end

  def validate_screener_type(type)
    %w[swing longterm].include?(type.to_s) ? type.to_s : "swing"
  end

  def parse_limit(limit_param)
    limit_param.presence&.to_i
  end

  def validate_priority(priority_param)
    %w[now normal].include?(priority_param.to_s) ? priority_param.to_s : "normal"
  end

  def parse_instrument_ids(ids_param)
    return [] unless ids_param.present?

    ids_param.to_s.split(",").map(&:to_i).reject(&:zero?)
  end

  def parse_symbols(symbols_param)
    return [] unless symbols_param.present?

    symbols_param.to_s.split(",").map(&:strip).reject(&:blank?)
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
    return false unless cache_data.is_a?(Hash)

    return false unless cache_data[:status] == "running"

    heartbeat = cache_data[:heartbeat]
    return false unless heartbeat.present?

    heartbeat_time = Time.zone.parse(heartbeat.to_s)
    return false unless heartbeat_time

    # Stream is running if heartbeat is within timeout window
    Time.current - heartbeat_time < WEBSOCKET_HEARTBEAT_TIMEOUT
  rescue ArgumentError, TypeError => e
    Rails.logger.warn("[ScreenersController] Invalid heartbeat format: #{e.message}")
    false
  end

  def find_existing_websocket_job(screener_type, instrument_ids, symbols)
    return nil unless solid_queue_installed?

    # Find jobs for WebsocketTickStreamerJob that match this stream
    # Check for recent jobs of this type (within lookback window)

    # Check pending jobs (created in last N minutes)
    pending_job = SolidQueue::Job
                  .where("class_name LIKE ?", "%WebsocketTickStreamerJob%")
                  .where(finished_at: nil)
                  .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
                  .where("created_at > ?", WEBSOCKET_JOB_LOOKBACK_MINUTES.minutes.ago)
                  .order(created_at: :desc)
                  .first

    return pending_job if pending_job

    # Check running jobs (claimed executions)
    running_execution = SolidQueue::ClaimedExecution
                       .joins(:job)
                       .where("solid_queue_jobs.class_name LIKE ?", "%WebsocketTickStreamerJob%")
                       .where("solid_queue_jobs.finished_at IS NULL")
                       .where("solid_queue_jobs.created_at > ?", WEBSOCKET_JOB_LOOKBACK_MINUTES.minutes.ago)
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
    Rails.logger.error("[ScreenersController] Error checking job status: #{e.message}")
    { running: false, error: e.message }
  end

  # Categorizes screener candidates into bullish, bearish, flag stocks, and recommendations
  # @param [Array] candidates Array of candidate hashes
  # @param [String] screener_type Type of screener: "swing" or "longterm"
  def categorize_candidates(candidates, screener_type)
    return if candidates.empty?

    build_position_lookup(candidates)
    categorize_by_sentiment(candidates, screener_type)
    sort_categories
  end

  # Builds a lookup hash of symbols that have open positions
  # @param [Array] candidates Array of candidate hashes
  def build_position_lookup(candidates)
    candidate_symbols = candidates.map { |c| c[:symbol] }.compact
    return if candidate_symbols.empty?

    # Optimize queries with includes and index_by
    instrument_ids = Instrument.where(symbol_name: candidate_symbols).pluck(:id)

    open_positions = Position.open
                             .where(symbol: candidate_symbols)
                             .includes(:instrument)
                             .index_by(&:symbol)

    paper_positions = PaperPosition.open
                                   .where(instrument_id: instrument_ids)
                                   .includes(:instrument)
                                   .index_by { |pos| pos.instrument&.symbol_name }

    # Create position lookup
    @position_lookup = {}
    open_positions.each do |symbol, pos|
      @position_lookup[symbol] = { mode: pos.live? ? "live" : "paper", position: pos }
    end

    paper_positions.each do |symbol, pos|
      @position_lookup[symbol] ||= { mode: "paper", position: pos }
    end
  end

  # Categorizes candidates by sentiment (bullish/bearish) and actionable status
  # @param [Array] candidates Array of candidate hashes
  # @param [String] screener_type Type of screener
  def categorize_by_sentiment(candidates, screener_type)
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
      recommendation = candidate[:recommendation].presence || generate_recommendation(
        candidate, indicators, score, is_bullish, screener_type
      )

      candidate_with_rec = candidate.merge(recommendation: recommendation)

      if is_bullish
        @bullish_stocks << candidate_with_rec
      else
        @bearish_stocks << candidate_with_rec
      end

      # Add to recommendations if actionable
      if actionable_candidate?(candidate, recommendation)
        @recommendations << candidate_with_rec
      end
    end
  end

  # Checks if a candidate is actionable (ready to trade)
  # @param [Hash] candidate Candidate hash
  # @param [String] recommendation Recommendation string
  # @return [Boolean] True if candidate is actionable
  def actionable_candidate?(candidate, recommendation)
    candidate[:setup_status] == "READY" ||
      candidate[:setup_status] == "ACCUMULATE" ||
      candidate[:trade_plan].present? ||
      candidate[:accumulation_plan].present? ||
      /(BUY|ACCUMULATE|Strong Buy|Buy)/i.match?(recommendation)
  end

  # Sorts all candidate categories by priority and score
  def sort_categories
    # Sort by score (descending)
    @bullish_stocks.sort_by! { |c| [-(c[:score] || 0)] }
    @bearish_stocks.sort_by! { |c| [-(c[:score] || 0)] }
    @flag_stocks.sort_by! { |c| -(c[:score] || 0) }

    # Sort recommendations by setup status priority, then by score
    @recommendations.sort_by! do |c|
      setup_priority = case c[:setup_status]
                       when "READY", "ACCUMULATE" then 0
                       when "WAIT_PULLBACK", "WAIT_BREAKOUT", "WAIT_DIP" then 1
                       when "IN_POSITION" then 2
                       else 3
                       end
      [setup_priority, -(c[:score] || 0)]
    end
  end

  # Determines if a candidate is bullish based on technical indicators
  # @param [Hash] candidate Candidate hash
  # @param [Hash] indicators Technical indicators hash
  # @param [String] screener_type Type of screener
  # @return [Boolean] True if candidate is bullish
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

  # Generates a trading recommendation based on score and sentiment
  # @param [Hash] _candidate Candidate hash (unused)
  # @param [Hash] _indicators Indicators hash (unused)
  # @param [Integer] score Candidate score
  # @param [Boolean] is_bullish Whether candidate is bullish
  # @param [String] _screener_type Type of screener (unused)
  # @return [String] Recommendation string
  def generate_recommendation(_candidate, _indicators, score, is_bullish, _screener_type)
    return "Avoid - Bearish signals" unless is_bullish

    case score
    when 75..Float::INFINITY
      "Strong Buy - High score with bullish indicators"
    when 60..74
      "Buy - Good opportunity with strong signals"
    when 50..59
      "Watch - Moderate signals, wait for confirmation"
    else
      "Wait - Weak signals, monitor for improvement"
    end
  end
end
