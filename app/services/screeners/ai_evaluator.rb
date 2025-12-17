# frozen_string_literal: true

module Screeners
  # Layer 3: AI Evaluation & Ranking
  # Reduces 30-40 high-quality setups → 10-15 AI-approved candidates
  #
  # AI evaluates:
  # - Market context
  # - Overcrowding detection
  # - Late-stage trend warnings
  # - Risk narratives
  # - Holding period estimation
  # - Confidence scoring
  #
  # Filters out candidates with:
  # - avoid: true
  # - confidence < 6.5
  class AIEvaluator < ApplicationService
    MAX_CALLS_PER_DAY = 50
    CACHE_TTL = 24.hours
    MIN_CONFIDENCE_THRESHOLD = 6.5

    def self.call(candidates: nil, limit: nil, screener_run_id: nil, **kwargs)
      # Support both positional and keyword arguments for backward compatibility
      candidates = kwargs[:candidates] || candidates if candidates.nil?
      screener_run_id = kwargs[:screener_run_id] || screener_run_id
      new(candidates: candidates, limit: limit, screener_run_id: screener_run_id).call
    end

    def initialize(candidates:, limit: nil, screener_run_id: nil)
      @candidates = candidates
      @limit = limit || AlgoConfig.fetch(%i[swing_trading ai_evaluation max_candidates]) || 15
      @screener_run_id = screener_run_id
      @config = AlgoConfig.fetch(%i[swing_trading ai_evaluation]) || {}
      @enabled = @config[:enabled] != false
      @model = @config[:model] || "gpt-4o-mini"
      @temperature = @config[:temperature] || 0.3
      @min_confidence = @config[:min_confidence] || MIN_CONFIDENCE_THRESHOLD
    end

    def call
      # If AI is disabled, return candidates sorted by combined score (highest first)
      unless @enabled
        Rails.logger.info("[Screeners::AIEvaluator] AI evaluation disabled, returning top candidates by score")
        return @candidates.sort_by do |c|
          screener_score = c[:score] || 0
          quality_score = c[:trade_quality_score] || 0
          -(screener_score * 0.5 + quality_score * 0.5)
        end.first(@limit)
      end

      # Check rate limit
      if rate_limit_exceeded?
        Rails.logger.warn("[Screeners::AIEvaluator] Rate limit exceeded, falling back to score-based ranking")
        return handle_rate_limit
      end

      # Ensure candidates are sorted by score (highest first) before AI evaluation
      # This ensures best candidates are evaluated first
      sorted_candidates = @candidates.sort_by do |c|
        screener_score = c[:score] || 0
        quality_score = c[:trade_quality_score] || 0
        # Combined: 50% screener score, 50% quality score
        -(screener_score * 0.5 + quality_score * 0.5)
      end

      Rails.logger.info(
        "[Screeners::AIEvaluator] Starting AI evaluation on #{sorted_candidates.size} candidates " \
        "(top combined score: #{(sorted_candidates.first&.dig(:score) || 0) * 0.5 + (sorted_candidates.first&.dig(:trade_quality_score) || 0) * 0.5})"
      )

      evaluated = []
      total_count = sorted_candidates.size
      processed_count = 0
      start_time = Time.current

      # Process highest scores first
      sorted_candidates.each do |candidate|
        processed_count += 1
        
        # Check idempotency - skip if already evaluated for this run
        ai_eval_id = generate_ai_eval_id(candidate)
        if already_evaluated?(ai_eval_id)
          Rails.logger.info("[Screeners::AIEvaluator] Skipping #{candidate[:symbol]} - already evaluated (#{ai_eval_id})")
          next
        end

        result = evaluate_candidate(candidate, ai_eval_id)
        
        if result
          # Filter: drop if avoid flag is true or confidence too low
          if result[:avoid] != true && result[:confidence] >= @min_confidence
            evaluated_candidate = candidate.merge(
              ai_confidence: result[:confidence],
              ai_stage: result[:stage],
              ai_momentum_trend: result[:momentum_trend],
              ai_price_position: result[:price_position],
              ai_entry_timing: result[:entry_timing],
              ai_continuation_bias: result[:continuation_bias],
              ai_holding_days: result[:holding_period_days] || result[:holding_days],
              ai_primary_risk: result[:primary_risk],
              ai_invalidate_if: result[:invalidate_if],
              # Legacy fields
              ai_risk: result[:risk],
              ai_comment: result[:comment] || result[:primary_risk],
              ai_avoid: result[:avoid] || false,
              ai_eval_id: ai_eval_id,
            )
            evaluated << evaluated_candidate

            # Persist AI evaluation result to database (with transaction)
            ActiveRecord::Base.transaction do
              persist_ai_evaluation_result(evaluated_candidate)
            end

            # Broadcast individual AI evaluation update (only after successful persistence)
            broadcast_ai_evaluation_update(evaluated_candidate, {
              total: total_count,
              processed: processed_count,
              evaluated: evaluated.size,
              started_at: start_time.iso8601,
              status: "running",
              elapsed: (Time.current - start_time).round(1),
              screener_run_id: @screener_run_id,
              stage: "ai_evaluated",
            })
          else
            # Mark as filtered but still persist status
            ActiveRecord::Base.transaction do
              mark_ai_filtered(candidate, result, ai_eval_id)
            end

            # Broadcast that candidate was filtered out
            broadcast_ai_evaluation_filtered(candidate, result, {
              total: total_count,
              processed: processed_count,
              evaluated: evaluated.size,
              started_at: start_time.iso8601,
              status: "running",
              elapsed: (Time.current - start_time).round(1),
              screener_run_id: @screener_run_id,
              stage: "ai_evaluated",
            })
          end
        else
          # Mark as failed
          ActiveRecord::Base.transaction do
            mark_ai_failed(candidate, ai_eval_id)
          end
        end
      end

      # Sort by confidence (highest first)
      sorted = evaluated.sort_by { |c| -c[:ai_confidence] }.first(@limit)
      
      # Broadcast completion
      broadcast_ai_evaluation_complete(sorted, {
        total: total_count,
        processed: processed_count,
        evaluated: sorted.size,
        started_at: start_time.iso8601,
        completed_at: Time.current.iso8601,
        duration: (Time.current - start_time).round(1),
        status: "completed",
      })

      sorted
    end

    private

    def generate_ai_eval_id(candidate)
      # Idempotency key: screener_run_id + instrument_id
      # Ensures same candidate is never evaluated twice in same run
      if @screener_run_id
        "#{@screener_run_id}-#{candidate[:instrument_id]}"
      else
        "#{Date.current}-#{candidate[:instrument_id]}"
      end
    end

    def already_evaluated?(ai_eval_id)
      return false unless ai_eval_id

      ScreenerResult.exists?(ai_eval_id: ai_eval_id, ai_status: ["evaluated", "failed"])
    end

    def evaluate_candidate(candidate, ai_eval_id)
      # Check cache first (by eval_id for run-specific caching)
      cache_key = "ai_eval:#{ai_eval_id}"
      cached = Rails.cache.read(cache_key)
      return cached if cached

      # Only evaluate READY setups
      setup_status = candidate[:setup_status] || candidate.dig(:metadata, :setup_status)
      unless setup_status == "READY"
        Rails.logger.debug("[Screeners::AIEvaluator] Skipping #{candidate[:symbol]} - setup_status is #{setup_status}, not READY")
        return nil
      end

      # Get ScreenerResult for indicator context
      screener_result = find_screener_result(candidate)
      return nil unless screener_result

      # Build indicator context
      indicator_context = Screeners::IndicatorContextBuilder.call(screener_result: screener_result)
      unless indicator_context
        Rails.logger.warn("[Screeners::AIEvaluator] Failed to build indicator context for #{candidate[:symbol]}")
        return nil
      end

      # Build prompt using new PromptBuilder
      prompt_data = Screeners::PromptBuilder.call(
        screener_result: screener_result,
        indicator_context: indicator_context,
      )

      # Call AI service with system and user messages
      ai_result = call_ai_with_prompt(prompt_data)

      return nil unless ai_result[:success]

      # Parse response (new JSON format)
      result = parse_response(ai_result[:content])
      return nil unless result

      # Cache result (by eval_id)
      Rails.cache.write(cache_key, result, expires_in: CACHE_TTL)

      # Track API call
      track_api_call

      # Track AI cost if screener_run_id is available (pass full ai_result for usage data)
      track_ai_cost(ai_result) if @screener_run_id

      result
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIEvaluator] Failed to evaluate candidate #{candidate[:symbol]}: #{e.message}")
      Rails.logger.debug { "[Screeners::AIEvaluator] Backtrace: #{e.backtrace.first(5).join("\n")}" }
      nil
    end

    def build_structured_input(candidate)
      indicators = candidate[:indicators] || {}
      metadata = candidate[:metadata] || {}
      mtf_data = candidate[:multi_timeframe] || {}
      quality_data = candidate[:trade_quality_breakdown] || {}

      # Extract key metrics
      latest_close = indicators[:latest_close] || metadata[:ltp]
      ema20 = indicators[:ema20]
      ema50 = indicators[:ema50]
      atr = indicators[:atr]

      # Calculate distance from breakout/EMA
      distance_from_breakout = if ema20 && latest_close
                                  ((latest_close - ema20) / ema20 * 100).round(2)
                                else
                                  nil
                                end

      # Calculate ATR %
      atr_percent = if atr && latest_close
                      (atr / latest_close * 100).round(2)
                    else
                      nil
                    end

      # Estimate RR potential
      rr_potential = estimate_rr_potential(candidate)

      # Extract volume trend
      volume = indicators[:volume] || {}
      volume_metrics = volume.is_a?(Hash) ? volume : {}
      volume_trend = if volume_metrics[:spike_ratio]
                       volume_metrics[:spike_ratio] >= 1.2 ? "increasing" : "stable"
                     else
                       "unknown"
                     end

      # Extract sector trend (if available)
      sector_trend = extract_sector_trend(candidate)

      # Check recent runup
      momentum = metadata[:momentum] || {}
      recent_runup = momentum[:change_5d] || 0
      recent_runup_status = if recent_runup > 15
                               "high"
                             elsif recent_runup > 10
                               "moderate"
                             else
                               "no"
                             end

      {
        symbol: candidate[:symbol],
        weekly_trend: mtf_data.dig(:trend_alignment, :aligned) ? "bullish" : "unknown",
        daily_structure: extract_structure_pattern(mtf_data, metadata),
        distance_from_breakout: distance_from_breakout ? "#{distance_from_breakout}%" : "unknown",
        atr_percent: atr_percent ? "#{atr_percent}%" : "unknown",
        rr_potential: rr_potential ? rr_potential.round(2).to_s : "unknown",
        volume_trend: volume_trend,
        sector_trend: sector_trend,
        recent_runup: recent_runup_status,
        trade_quality_score: candidate[:trade_quality_score] || candidate[:score] || 0,
        mtf_score: candidate[:mtf_score] || mtf_data[:multi_timeframe_score] || 0,
      }
    end

    def extract_structure_pattern(mtf_data, metadata)
      # Check for HH-HL pattern
      return "HH-HL" if metadata[:structure_pattern] == "HH-HL"

      # Check for BOS
      if mtf_data[:structure] && mtf_data[:structure][:bos]
        return "BOS-#{mtf_data[:structure][:bos][:type]}"
      end

      "trending"
    end

    def extract_sector_trend(candidate)
      # TODO: Implement sector trend analysis
      # For now, return neutral
      "neutral"
    end

    def estimate_rr_potential(candidate)
      indicators = candidate[:indicators] || {}
      metadata = candidate[:metadata] || {}
      series_data = {
        latest_close: indicators[:latest_close] || metadata[:ltp],
        ema20: indicators[:ema20],
        ema50: indicators[:ema50],
        atr: indicators[:atr],
      }

      latest_close = series_data[:latest_close]
      ema20 = series_data[:ema20]
      atr = series_data[:atr]

      return nil unless latest_close && atr

      entry_price = ema20 || latest_close
      stop_loss = entry_price - (atr * 2)
      risk = (entry_price - stop_loss).abs
      return nil if risk.zero?

      target_price = entry_price + (risk * 2.5)
      reward = (target_price - entry_price).abs
      reward / risk
    end

    def call_ai_with_prompt(prompt_data)
      # Use Ollama service directly for deterministic prompts
      # Ollama supports system/user message format
      system_message = prompt_data[:system_message]
      user_message = prompt_data[:user_message]

      # Combine into single prompt for AI::UnifiedService (if it doesn't support system messages)
      # Otherwise, pass both separately
      combined_prompt = "#{system_message}\n\n#{user_message}"

      AI::UnifiedService.call(
        prompt: combined_prompt,
        provider: @config[:provider] || "ollama",
        model: @model,
        temperature: @temperature,
      )
    end

    def parse_response(response)
      return nil unless response

      # Try to extract JSON from response (handle markdown code blocks)
      json_text = response.strip
      json_text = json_text.gsub(/```json\s*/, "").gsub(/```\s*$/, "") if json_text.include?("```")

      parsed = JSON.parse(json_text)

      # Validate confidence range (0.0 to 10.0)
      confidence = parsed["confidence"]&.to_f || 0
      confidence = [[confidence, 0.0].max, 10.0].min

      # Validate enum values
      stage = parsed["stage"]
      stage = "middle" unless %w[early middle late].include?(stage)

      momentum_trend = parsed["momentum_trend"]
      momentum_trend = "stable" unless %w[strengthening stable weakening].include?(momentum_trend)

      price_position = parsed["price_position"]
      price_position = "slightly_extended" unless %w[near_value slightly_extended extended].include?(price_position)

      entry_timing = parsed["entry_timing"]
      entry_timing = "wait" unless %w[immediate wait].include?(entry_timing)

      continuation_bias = parsed["continuation_bias"]
      continuation_bias = "medium" unless %w[high medium low].include?(continuation_bias)

      {
        confidence: confidence,
        stage: stage,
        momentum_trend: momentum_trend,
        price_position: price_position,
        entry_timing: entry_timing,
        continuation_bias: continuation_bias,
        holding_period_days: parsed["holding_period_days"] || "7-14",
        primary_risk: parsed["primary_risk"] || "",
        invalidate_if: parsed["invalidate_if"] || "",
        # Legacy fields for backward compatibility
        risk: map_risk_from_stage(stage, momentum_trend),
        holding_days: parsed["holding_period_days"] || "7-14",
        comment: parsed["primary_risk"] || "",
        avoid: entry_timing == "wait" || confidence < 6.0,
      }
    rescue JSON::ParserError => e
      Rails.logger.error("[Screeners::AIEvaluator] Failed to parse JSON response: #{e.message}")
      Rails.logger.debug { "[Screeners::AIEvaluator] Response: #{response}" }
      nil
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIEvaluator] Error parsing response: #{e.message}")
      nil
    end

    def map_risk_from_stage(stage, momentum_trend)
      return "high" if stage == "late" || momentum_trend == "weakening"
      return "low" if stage == "early" && momentum_trend == "strengthening"

      "medium"
    end

    def find_screener_result(candidate)
      if @screener_run_id && candidate[:instrument_id]
        ScreenerResult.find_by(
          screener_run_id: @screener_run_id,
          instrument_id: candidate[:instrument_id],
          screener_type: "swing",
        )
      elsif candidate[:instrument_id]
        ScreenerResult.where(
          instrument_id: candidate[:instrument_id],
          screener_type: "swing",
        ).order(analyzed_at: :desc).first
      end
    end

    def rate_limit_exceeded?
      today = Time.zone.today.to_s
      cache_key = "ai_evaluator_calls:#{today}"
      calls_today = Rails.cache.read(cache_key) || 0
      calls_today >= MAX_CALLS_PER_DAY
    end

    def track_api_call
      today = Time.zone.today.to_s
      cache_key = "ai_evaluator_calls:#{today}"
      calls_today = Rails.cache.read(cache_key) || 0
      Rails.cache.write(cache_key, calls_today + 1, expires_in: 1.day)
    end

    def track_ai_cost(ai_result)
      return unless @screener_run_id && ai_result

      screener_run = ScreenerRun.find_by(id: @screener_run_id)
      return unless screener_run

      # Extract token usage from AI result (if available)
      input_tokens = ai_result[:usage]&.dig(:prompt_tokens) || ai_result[:input_tokens] || 0
      output_tokens = ai_result[:usage]&.dig(:completion_tokens) || ai_result[:output_tokens] || 0

      ScreenerRuns::AICostTracker.track_call(
        screener_run: screener_run,
        model: @model,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIEvaluator] Failed to track AI cost: #{e.message}")
      # Don't fail evaluation if cost tracking fails
    end

    def handle_rate_limit
      Rails.logger.warn("[Screeners::AIEvaluator] Rate limit exceeded (#{MAX_CALLS_PER_DAY} calls/day)")
      # Return candidates sorted by trade quality score only
      @candidates.sort_by { |c| -(c[:trade_quality_score] || c[:score] || 0) }.first(@limit)
    end

    def broadcast_ai_evaluation_update(candidate, progress_data)
      # Broadcast individual AI evaluation result for live UI updates
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "ai_evaluation_added",
          screener_type: "swing",
          screener_run_id: progress_data[:screener_run_id],
          stage: progress_data[:stage] || "ai_evaluated",
          record: candidate,
          progress: progress_data,
        },
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIEvaluator] Failed to broadcast AI evaluation: #{e.message}")
    end

    def broadcast_ai_evaluation_filtered(candidate, result, progress_data)
      # Broadcast when candidate is filtered out by AI
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "ai_evaluation_filtered",
          screener_type: "swing",
          screener_run_id: progress_data[:screener_run_id],
          stage: progress_data[:stage] || "ai_evaluated",
          symbol: candidate[:symbol],
          reason: result[:avoid] ? "avoided" : "low_confidence",
          confidence: result[:confidence],
          progress: progress_data,
        },
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIEvaluator] Failed to broadcast filtered candidate: #{e.message}")
    end

    def broadcast_ai_evaluation_complete(evaluated_candidates, progress_data)
      # Broadcast completion of AI evaluation phase
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "ai_evaluation_complete",
          screener_type: "swing",
          screener_run_id: @screener_run_id,
          stage: "ai_evaluated",
          candidate_count: evaluated_candidates.size,
          progress: progress_data,
        },
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIEvaluator] Failed to broadcast completion: #{e.message}")
    end

    def persist_ai_evaluation_result(candidate)
      # Update existing ScreenerResult with AI evaluation data
      return unless candidate[:instrument_id]

      screener_result = if @screener_run_id
                          ScreenerResult.find_by(
                            screener_run_id: @screener_run_id,
                            instrument_id: candidate[:instrument_id],
                            screener_type: "swing",
                          )
                        else
                          ScreenerResult.find_by(
                            instrument_id: candidate[:instrument_id],
                            screener_type: "swing",
                          )
                        end

      return unless screener_result

      # Update with AI evaluation fields
      screener_result.update_columns(
        ai_confidence: candidate[:ai_confidence],
        ai_stage: candidate[:ai_stage],
        ai_momentum_trend: candidate[:ai_momentum_trend],
        ai_price_position: candidate[:ai_price_position],
        ai_entry_timing: candidate[:ai_entry_timing],
        ai_continuation_bias: candidate[:ai_continuation_bias],
        ai_holding_days: candidate[:ai_holding_days],
        ai_primary_risk: candidate[:ai_primary_risk],
        ai_invalidate_if: candidate[:ai_invalidate_if],
        # Legacy fields
        ai_risk: candidate[:ai_risk],
        ai_comment: candidate[:ai_comment],
        ai_avoid: candidate[:ai_avoid] || false,
        ai_eval_id: candidate[:ai_eval_id],
        ai_status: "evaluated",
        stage: "ai_evaluated",
        trade_quality_score: candidate[:trade_quality_score],
        trade_quality_breakdown: candidate[:trade_quality_breakdown]&.to_json,
      )
    rescue StandardError => e
      Rails.logger.error(
        "[Screeners::AIEvaluator] Failed to persist AI evaluation for #{candidate[:symbol]}: #{e.message}"
      )
      # Don't fail the entire evaluation if one save fails
    end

    def mark_ai_filtered(candidate, result, ai_eval_id)
      return unless candidate[:instrument_id]

      screener_result = if @screener_run_id
                          ScreenerResult.find_by(
                            screener_run_id: @screener_run_id,
                            instrument_id: candidate[:instrument_id],
                            screener_type: "swing",
                          )
                        else
                          ScreenerResult.find_by(
                            instrument_id: candidate[:instrument_id],
                            screener_type: "swing",
                          )
                        end

      return unless screener_result

      screener_result.update_columns(
        ai_eval_id: ai_eval_id,
        ai_status: "skipped",
        ai_avoid: result[:avoid] || false,
        ai_confidence: result[:confidence],
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIEvaluator] Failed to mark filtered: #{e.message}")
    end

    def mark_ai_failed(candidate, ai_eval_id)
      return unless candidate[:instrument_id]

      screener_result = if @screener_run_id
                          ScreenerResult.find_by(
                            screener_run_id: @screener_run_id,
                            instrument_id: candidate[:instrument_id],
                            screener_type: "swing",
                          )
                        else
                          ScreenerResult.find_by(
                            instrument_id: candidate[:instrument_id],
                            screener_type: "swing",
                          )
                        end

      return unless screener_result

      screener_result.update_columns(
        ai_eval_id: ai_eval_id,
        ai_status: "failed",
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIEvaluator] Failed to mark failed: #{e.message}")
    end
  end

  # Backward compatibility alias
  AIRanker = AIEvaluator
end

