# frozen_string_literal: true

module Screeners
  class AIRanker < ApplicationService
    MAX_CALLS_PER_DAY = 50
    CACHE_TTL = 24.hours

    def self.call(candidates: nil, limit: nil, **kwargs)
      # Support both positional and keyword arguments for backward compatibility
      candidates = kwargs[:candidates] || candidates if candidates.nil?
      new(candidates: candidates, limit: limit).call
    end

    def initialize(candidates:, limit: nil)
      @candidates = candidates
      @limit = limit || AlgoConfig.fetch(%i[swing_trading ai_ranking max_candidates]) || 20
      @config = AlgoConfig.fetch(%i[swing_trading ai_ranking]) || {}
      @enabled = @config[:enabled] != false
      @model = @config[:model] || "gpt-4o-mini"
      @temperature = @config[:temperature] || 0.3
    end

    def call
      return @candidates.first(@limit) unless @enabled

      # Check rate limit
      return handle_rate_limit if rate_limit_exceeded?

      ranked = []

      @candidates.each do |candidate|
        result = rank_candidate(candidate)
        next unless result

        ranked << candidate.merge(
          ai_score: result[:score],
          ai_confidence: result[:confidence],
          ai_summary: result[:summary],
          ai_holding_days: result[:holding_days],
          ai_risk: result[:risk],
          ai_timeframe_alignment: result[:timeframe_alignment],
        )
      end

      # Sort by combined score (screener score + AI score)
      ranked.sort_by { |c| -(c[:score] + (c[:ai_score] || 0)) }.first(@limit)
    end

    private

    def rank_candidate(candidate)
      # Check cache first
      cache_key = "ai_rank:#{candidate[:instrument_id]}:#{candidate[:symbol]}"
      cached = Rails.cache.read(cache_key)
      return cached if cached

      # Build prompt
      prompt = build_prompt(candidate)

      # Call OpenAI API
      response = call_openai(prompt)
      return nil unless response

      # Parse response
      result = parse_response(response)
      return nil unless result

      # Cache result
      Rails.cache.write(cache_key, result, expires_in: CACHE_TTL)

      # Track API call
      track_api_call

      result
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIRanker] Failed to rank candidate #{candidate[:symbol]}: #{e.message}")
      nil
    end

    def build_prompt(candidate)
      indicators = candidate[:indicators] || candidate[:daily_indicators] || {}
      metadata = candidate[:metadata] || {}
      mtf_data = candidate[:multi_timeframe] || metadata[:multi_timeframe] || {}

      mtf_summary = build_mtf_summary(mtf_data)

      <<~PROMPT
        You are a technical analysis expert for swing trading (holding period: 5-20 days).
        Analyze this stock using MULTI-TIMEFRAME analysis (15m, 1h, 1d, 1w).

        Provide a JSON response with:
        - score: 0-100 (overall quality score considering all timeframes)
        - confidence: 0-100 (confidence in the analysis)
        - summary: Brief 2-3 sentence multi-timeframe summary
        - holding_days: Estimated holding period (5-20 days)
        - risk: "low", "medium", or "high"
        - timeframe_alignment: "excellent", "good", "fair", or "poor"

        Stock: #{candidate[:symbol]}
        Current Score: #{candidate[:score]}/100
        MTF Score: #{mtf_data[:score] || candidate[:mtf_score] || 'N/A'}/100

        Daily Timeframe Indicators:
        - EMA20: #{indicators[:ema20]&.round(2) || 'N/A'}
        - EMA50: #{indicators[:ema50]&.round(2) || 'N/A'}
        - EMA200: #{indicators[:ema200]&.round(2) || 'N/A'}
        - RSI: #{indicators[:rsi]&.round(2) || 'N/A'}
        - ADX: #{indicators[:adx]&.round(2) || 'N/A'}
        - ATR: #{indicators[:atr]&.round(2) || 'N/A'}
        - Supertrend: #{indicators[:supertrend]&.dig(:direction) || 'N/A'}

        #{mtf_summary}

        #{"Trend Alignment: #{metadata[:trend_alignment].join(', ')}" if metadata[:trend_alignment]}

        #{"Momentum: #{metadata[:momentum][:change_5d] || 'N/A'}% (5-day change)" if metadata[:momentum]}

        Consider:
        - Higher timeframes (weekly, daily) should show bullish trend
        - Lower timeframes (1h, 15m) should confirm entry timing
        - Support/resistance levels from weekly and daily charts
        - Overall structure alignment across all timeframes

        Provide ONLY valid JSON in this format:
        {
          "score": 75,
          "confidence": 80,
          "summary": "Strong bullish trend across all timeframes with good momentum...",
          "holding_days": 12,
          "risk": "medium",
          "timeframe_alignment": "excellent"
        }
      PROMPT
    end

    def build_mtf_summary(mtf_data)
      return "" if mtf_data.empty?

      summary = "\nMulti-Timeframe Analysis:\n"

      if mtf_data[:trend_alignment]
        ta = mtf_data[:trend_alignment]
        summary += "- Trend Alignment: #{ta[:aligned] ? 'ALIGNED' : 'NOT ALIGNED'} "
        summary += "(Bullish: #{ta[:bullish_count]}, Bearish: #{ta[:bearish_count]})\n"
      end

      if mtf_data[:momentum_alignment]
        ma = mtf_data[:momentum_alignment]
        summary += "- Momentum Alignment: #{ma[:aligned] ? 'ALIGNED' : 'NOT ALIGNED'} "
        summary += "(Bullish: #{ma[:bullish_count]}, Bearish: #{ma[:bearish_count]})\n"
      end

      if mtf_data[:timeframes_analyzed]&.any?
        summary += "- Timeframes Analyzed: #{mtf_data[:timeframes_analyzed].join(', ')}\n"
      end

      if mtf_data[:entry_recommendations]&.any?
        summary += "- Entry Recommendations: #{mtf_data[:entry_recommendations].size} found\n"
      end

      summary
    end

    def call_openai(prompt)
      return nil unless openai_api_key

      require "ruby/openai" unless defined?(Ruby::OpenAI)

      client = Ruby::OpenAI::Client.new(access_token: openai_api_key)
      response = client.chat(
        parameters: {
          model: @model,
          messages: [
            { role: "system", content: "You are a technical analysis expert. Always respond with valid JSON only." },
            { role: "user", content: prompt },
          ],
          temperature: @temperature,
          max_tokens: 200,
        },
      )

      response.dig("choices", 0, "message", "content")
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIRanker] OpenAI API error: #{e.message}")
      nil
    end

    def parse_response(response)
      return nil unless response

      # Try to extract JSON from response (handle markdown code blocks)
      json_text = response.strip
      json_text = json_text.gsub(/```json\s*/, "").gsub(/```\s*$/, "") if json_text.include?("```")

        parsed = JSON.parse(json_text)
        {
          score: parsed["score"]&.to_f || 0,
          confidence: parsed["confidence"]&.to_f || 0,
          summary: parsed["summary"] || "",
          holding_days: parsed["holding_days"]&.to_i || 10,
          risk: parsed["risk"]&.downcase || "medium",
          timeframe_alignment: parsed["timeframe_alignment"]&.downcase || "fair",
        }
    rescue JSON::ParserError => e
      Rails.logger.error("[Screeners::AIRanker] Failed to parse JSON response: #{e.message}")
      Rails.logger.debug { "[Screeners::AIRanker] Response: #{response}" }
      nil
    rescue StandardError => e
      Rails.logger.error("[Screeners::AIRanker] Error parsing response: #{e.message}")
      nil
    end

    def openai_api_key
      ENV.fetch("OPENAI_API_KEY", nil)
    end

    def rate_limit_exceeded?
      today = Time.zone.today.to_s
      cache_key = "ai_ranker_calls:#{today}"
      calls_today = Rails.cache.read(cache_key) || 0
      calls_today >= MAX_CALLS_PER_DAY
    end

    def track_api_call
      today = Time.zone.today.to_s
      cache_key = "ai_ranker_calls:#{today}"
      calls_today = Rails.cache.read(cache_key) || 0
      Rails.cache.write(cache_key, calls_today + 1, expires_in: 1.day)
    end

    def handle_rate_limit
      Rails.logger.warn("[Screeners::AIRanker] Rate limit exceeded (#{MAX_CALLS_PER_DAY} calls/day)")
      # Return candidates sorted by screener score only
      @candidates.sort_by { |c| -c[:score] }.first(@limit)
    end
  end
end
