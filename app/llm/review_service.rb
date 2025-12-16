# frozen_string_literal: true

module LLM
  # Service to review TradeRecommendation using LLM
  # LLM can ONLY provide advisory information, NEVER approve/reject
  # System continues working even if LLM fails
  class ReviewService < ApplicationService
    def self.call(trade_recommendation, provider: nil, config: {})
      new(trade_recommendation, provider: provider, config: config).call
    end

    def initialize(trade_recommendation, provider: nil, config: {})
      @recommendation = trade_recommendation
      @provider = provider || determine_provider
      @config = config
    end

    def call
      return disabled_response unless enabled?

      # Build prompt
      prompt = build_prompt

      # Call AI service
      ai_result = call_ai_service(prompt)
      return default_response unless ai_result[:success]

      # Parse response into contract
      contract = ReviewContract.parse(ai_result[:content])

      # Build response
      {
        success: true,
        contract: contract,
        provider: @provider,
        cached: ai_result[:cached] || false,
      }
    rescue StandardError => e
      Rails.logger.error("[LLM::ReviewService] Review failed: #{e.message}")
      default_response
    end

    private

    def enabled?
      Trading::Config.llm_enabled?
    end

    def determine_provider
      Trading::Config.config_value("trading", "llm", "provider") || "auto"
    end

    def build_prompt
      <<~PROMPT
        You are a quantitative trading analyst reviewing a trade recommendation that has already been approved by deterministic rules.

        Trade Details:
        - Symbol: #{@recommendation.symbol}
        - Timeframe: #{@recommendation.timeframe}
        - Entry: ₹#{@recommendation.entry_price}
        - Stop Loss: ₹#{@recommendation.stop_loss}
        - Target: ₹{@recommendation.target_prices.first&.first || 'N/A'}
        - Risk-Reward: #{@recommendation.risk_reward}R
        - Confidence: #{@recommendation.confidence_score}/100
        - Quantity: #{@recommendation.quantity}

        Deterministic Reasoning:
        #{@recommendation.reasoning.join("\n")}

        Your Task:
        Review this trade and provide ADVISORY feedback only. You CANNOT approve or reject the trade.

        Respond with STRICT JSON only:
        {
          "advisory_level": "info" | "warning" | "block_auto",
          "confidence_adjustment": -10 to +10 (integer),
          "notes": "Brief explanation"
        }

        Advisory Levels:
        - "info": Informational note, no action needed
        - "warning": Warning but trade can proceed
        - "block_auto": Block automated execution, require manual review (use sparingly)

        Confidence Adjustment:
        - Range: -10 to +10
        - Adjusts the deterministic confidence score
        - Use 0 if no adjustment needed

        Rules:
        - You CANNOT return "approved" or "rejected"
        - You can only provide advisory feedback
        - System will proceed with trade unless advisory_level is "block_auto"
        - Be concise and analytical

        Respond with JSON only, no other text.
      PROMPT
    end

    def call_ai_service(prompt)
      model = @config[:model] || Trading::Config.config_value("trading", "llm", "model")

      AI::UnifiedService.call(
        prompt: prompt,
        provider: @provider,
        model: model,
        temperature: 0.3,
        max_tokens: 200,
        cache: true,
      )
    end

    def default_response
      {
        success: false,
        contract: ReviewContract.default_contract,
        provider: @provider,
        error: true,
      }
    end

    def disabled_response
      {
        success: false,
        contract: ReviewContract.default_contract,
        provider: nil,
        disabled: true,
      }
    end
  end
end
