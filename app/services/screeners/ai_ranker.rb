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

    def self.call(candidates: nil, limit: nil, **kwargs)
      # Support both positional and keyword arguments for backward compatibility
      candidates = kwargs[:candidates] || candidates if candidates.nil?
      new(candidates: candidates, limit: limit).call
    end

    def initialize(candidates:, limit: nil)
      @candidates = candidates
      @limit = limit || AlgoConfig.fetch(%i[swing_trading ai_evaluation max_candidates]) || 15
      @config = AlgoConfig.fetch(%i[swing_trading ai_evaluation]) || {}
      @enabled = @config[:enabled] != false
      @model = @config[:model] || "gpt-4o-mini"
      @temperature = @config[:temperature] || 0.3
      @min_confidence = @config[:min_confidence] || MIN_CONFIDENCE_THRESHOLD
    end

    def call
      return @candidates.first(@limit) unless @enabled

      # Check rate limit
      return handle_rate_limit if rate_limit_exceeded?

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
        result = evaluate_candidate(candidate)
        
        if result
          # Filter: drop if avoid flag is true or confidence too low
          if result[:avoid] != true && result[:confidence] >= @min_confidence
            evaluated_candidate = candidate.merge(
              ai_confidence: result[:confidence],
              ai_risk: result[:risk],
              ai_holding_days: result[:holding_days],
              ai_comment: result[:comment],
              ai_avoid: result[:avoid] || false,
            )
            evaluated << evaluated_candidate

            # Broadcast individual AI evaluation update
            broadcast_ai_evaluation_update(evaluated_candidate, {
              total: total_count,
              processed: processed_count,
              evaluated: evaluated.size,
              started_at: start_time.iso8601,
              status: "running",
              elapsed: (Time.current - start_time).round(1),
            })
          else
            # Broadcast that candidate was filtered out
            broadcast_ai_evaluation_filtered(candidate, result, {
              total: total_count,
              processed: processed_count,
              evaluated: evaluated.size,
              started_at: start_time.iso8601,
              status: "running",
              elapsed: (Time.current - start_time).round(1),
            })
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

    def evaluate_candidate(candidate)
      # Check cache first
      cache_key = "ai_eval:#{candidate[:instrument_id]}:#{candidate[:symbol]}"
      cached = Rails.cache.read(cache_key)
      return cached if cached

      # Build structured input
      structured_input = build_structured_input(candidate)

      # Build prompt
      prompt = build_prompt(structured_input)

      # Call AI service
      ai_result = AI::UnifiedService.call(
        prompt: prompt,
        provider: @config[:provider] || "auto",
        model: @model,
        temperature: @temperature,
      )

      return nil unless ai_result[:success]

      # Parse response
      result = parse_response(ai_result[:content])
      return nil unless result

      # Cache result
      Rails.cache.write(cache_key, result, expires_in: CACHE_TTL)

      # Track API call
      track_api_call

      result
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIEvaluator] Failed to evaluate candidate #{candidate[:symbol]}: #{e.message}")
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

    def build_prompt(structured_input)
      <<~PROMPT
        You are a professional swing trading analyst evaluating trade setups.

        Analyze this candidate using structured data and provide judgment on:
        1. Market context (sector momentum, overall market phase)
        2. Overcrowding (too many similar setups = lower edge)
        3. Late-stage trend warnings (extended moves, exhaustion signals)
        4. Risk narratives (what could go wrong)
        5. Holding period estimation (realistic timeframe)
        6. Confidence scoring (0-10 scale)

        Structured Input:
        {
          "symbol": "#{structured_input[:symbol]}",
          "weekly_trend": "#{structured_input[:weekly_trend]}",
          "daily_structure": "#{structured_input[:daily_structure]}",
          "distance_from_breakout": "#{structured_input[:distance_from_breakout]}",
          "atr_percent": "#{structured_input[:atr_percent]}",
          "rr_potential": "#{structured_input[:rr_potential]}",
          "volume_trend": "#{structured_input[:volume_trend]}",
          "sector_trend": "#{structured_input[:sector_trend]}",
          "recent_runup": "#{structured_input[:recent_runup]}",
          "trade_quality_score": #{structured_input[:trade_quality_score]},
          "mtf_score": #{structured_input[:mtf_score]}
        }

        Provide ONLY valid JSON in this exact format:
        {
          "confidence": 8.2,
          "risk": "low",
          "holding_days": "7-15",
          "comment": "Fresh continuation setup with good structure and not extended. Sector momentum supports further upside.",
          "avoid": false
        }

        Rules:
        - confidence: 0-10 scale (6.5+ required to pass)
        - risk: "low", "medium", or "high"
        - holding_days: realistic range like "7-15" or "10-20"
        - comment: 1-2 sentence explanation
        - avoid: true if setup should be skipped (overcrowded, late-stage, high risk)
      PROMPT
    end

    def parse_response(response)
      return nil unless response

      # Try to extract JSON from response (handle markdown code blocks)
      json_text = response.strip
      json_text = json_text.gsub(/```json\s*/, "").gsub(/```\s*$/, "") if json_text.include?("```")

      parsed = JSON.parse(json_text)
      {
        confidence: parsed["confidence"]&.to_f || 0,
        risk: parsed["risk"]&.downcase || "medium",
        holding_days: parsed["holding_days"] || "10-15",
        comment: parsed["comment"] || "",
        avoid: parsed["avoid"] == true,
      }
    rescue JSON::ParserError => e
      Rails.logger.error("[Screeners::AIEvaluator] Failed to parse JSON response: #{e.message}")
      Rails.logger.debug { "[Screeners::AIEvaluator] Response: #{response}" }
      nil
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIEvaluator] Error parsing response: #{e.message}")
      nil
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
          candidate_count: evaluated_candidates.size,
          progress: progress_data,
        },
      )
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIEvaluator] Failed to broadcast completion: #{e.message}")
    end
  end

  # Backward compatibility alias
  AIRanker = AIEvaluator
end

