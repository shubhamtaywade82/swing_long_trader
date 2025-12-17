# frozen_string_literal: true

module Screeners
  # Builds deterministic AI prompt for swing/longterm trade setup evaluation
  # LOCKED PROMPT STRUCTURE - DO NOT TWEAK WITHOUT VERSIONING
  class PromptBuilder < ApplicationService
    PROMPT_VERSION = "1.0.0"

    def self.call(screener_result:, indicator_context:)
      new(screener_result: screener_result, indicator_context: indicator_context).call
    end

    def initialize(screener_result:, indicator_context:)
      @screener_result = screener_result
      @indicator_context = indicator_context
    end

    def call
      {
        system_message: build_system_message,
        user_message: build_user_message,
        version: PROMPT_VERSION,
      }
    end

    private

    def build_system_message
      <<~SYSTEM
        You are a professional trading assistant helping evaluate swing and long-term trade setups.

        You do NOT calculate indicators.
        You do NOT predict prices.
        You do NOT give buy/sell commands.
        You only interpret the provided data.

        Your job is to analyze:
        - How momentum and trend evolved to reach the current setup
        - Whether the setup looks early, healthy, or extended
        - Whether entry timing is appropriate or should be delayed
        - What risks or invalidation conditions exist

        You must base your analysis STRICTLY on the provided data.
        If information is insufficient, say so explicitly.

        Respond ONLY in valid JSON.
      SYSTEM
    end

    def build_user_message
      task_definition + "\n\n" + output_schema + "\n\n" + stock_specific_data
    end

    def output_schema
      <<~SCHEMA
        Respond ONLY in valid JSON using this exact structure:

        {
          "confidence": number,
          "stage": "early" | "middle" | "late",
          "momentum_trend": "strengthening" | "stable" | "weakening",
          "price_position": "near_value" | "slightly_extended" | "extended",
          "entry_timing": "immediate" | "wait",
          "continuation_bias": "high" | "medium" | "low",
          "holding_period_days": "x-y",
          "primary_risk": "string",
          "invalidate_if": "string"
        }

        Validation rules:
        - confidence: 0.0 to 10.0 (required)
        - stage: "early", "middle", or "late" (required)
        - momentum_trend: "strengthening", "stable", or "weakening" (required)
        - price_position: "near_value", "slightly_extended", or "extended" (required)
        - entry_timing: "immediate" or "wait" (required)
        - continuation_bias: "high", "medium", or "low" (required)
        - holding_period_days: range string like "7-14" or "10-20" (required)
        - primary_risk: description of main risk (required)
        - invalidate_if: conditions that would invalidate setup (required)
      SCHEMA
    end

    def task_definition
      <<~TASK
        Analyze the following trade setup using the provided screener data and indicator evolution.

        Your tasks:
        1. Describe how momentum and trend strength have evolved over the last few candles.
        2. Identify the stage of the move (early, middle, late).
        3. Assess whether the current price appears near value or extended.
        4. Decide whether the setup is suitable for immediate entry or should wait.
        5. Highlight any caution, exhaustion, or failure risks.
        6. Clearly state conditions that would invalidate the setup.

        Do not calculate indicators.
        Do not predict future prices.
        Do not suggest position size.

        Use ONLY the data provided below.
      TASK
    end

    def stock_specific_data
      indicators = @screener_result.indicators_hash
      metadata = @screener_result.metadata_hash
      mtf_data = @screener_result.multi_timeframe_hash

      setup_data = {
        symbol: @screener_result.symbol,
        strategy: @screener_result.screener_type,
        setup_status: @screener_result.setup_status || metadata["setup_status"],
        scores: {
          base_score: @screener_result.base_score || 0,
          mtf_score: @screener_result.mtf_score || 0,
          quality_score: @screener_result.trade_quality_score || 0,
        },
        trend_alignment: extract_trend_alignment(mtf_data),
        current_price: extract_current_price(indicators, metadata),
        levels: extract_levels(indicators, metadata),
        indicator_context: @indicator_context || {},
        market_context: extract_market_context(metadata, mtf_data),
      }

      "SETUP DATA:\n\n#{JSON.pretty_generate(setup_data)}"
    end

    def extract_trend_alignment(mtf_data)
      trend_alignment = mtf_data["trend_alignment"] || {}
      {
        weekly: trend_alignment["weekly"] || "unknown",
        daily: trend_alignment["daily"] || "unknown",
        hourly: trend_alignment["hourly"] || "unknown",
      }
    end

    def extract_current_price(indicators, metadata)
      indicators["latest_close"] || indicators["ltp"] || metadata["ltp"] || 0
    end

    def extract_levels(indicators, metadata)
      ema20 = indicators["ema20"]
      latest_close = extract_current_price(indicators, metadata)

      {
        recent_swing_low: metadata["recent_swing_low"] || (ema20 ? (ema20 * 0.95).round(2) : nil),
        recent_swing_high: metadata["recent_swing_high"] || (latest_close ? (latest_close * 1.05).round(2) : nil),
      }
    end

    def extract_market_context(metadata, mtf_data)
      {
        index_trend: mtf_data["index_trend"] || metadata["index_trend"] || "unknown",
        sector_strength: metadata["sector_strength"] || "unknown",
      }
    end
  end
end
