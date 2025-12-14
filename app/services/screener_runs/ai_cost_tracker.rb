# frozen_string_literal: true

module ScreenerRuns
  # Tracks AI costs per evaluation
  class AICostTracker < ApplicationService
    # Estimated costs per token (approximate, adjust based on actual provider)
    COST_PER_1K_INPUT_TOKENS = {
      "gpt-4o-mini" => 0.00015, # $0.15 per 1M input tokens
      "gpt-4o" => 0.0025, # $2.50 per 1M input tokens
      "gpt-4" => 0.03, # $30 per 1M input tokens
    }.freeze

    COST_PER_1K_OUTPUT_TOKENS = {
      "gpt-4o-mini" => 0.0006, # $0.60 per 1M output tokens
      "gpt-4o" => 0.01, # $10 per 1M output tokens
      "gpt-4" => 0.06, # $60 per 1M output tokens
    }.freeze

    def self.track_call(screener_run:, model:, input_tokens:, output_tokens:)
      new(screener_run: screener_run, model: model, input_tokens: input_tokens, output_tokens: output_tokens).track
    end

    def initialize(screener_run:, model:, input_tokens:, output_tokens:)
      @screener_run = screener_run
      @model = model || "gpt-4o-mini"
      @input_tokens = input_tokens || 0
      @output_tokens = output_tokens || 0
    end

    def track
      cost = calculate_cost
      
      @screener_run.increment!(:ai_calls_count)
      @screener_run.increment!(:ai_cost, cost)
      
      {
        success: true,
        cost: cost,
        total_cost: @screener_run.reload.ai_cost,
        total_calls: @screener_run.ai_calls_count,
      }
    rescue StandardError => e
      Rails.logger.error("[ScreenerRuns::AICostTracker] Failed to track cost: #{e.message}")
      {
        success: false,
        error: e.message,
      }
    end

    private

    def calculate_cost
      input_cost_per_1k = COST_PER_1K_INPUT_TOKENS[@model] || COST_PER_1K_INPUT_TOKENS["gpt-4o-mini"]
      output_cost_per_1k = COST_PER_1K_OUTPUT_TOKENS[@model] || COST_PER_1K_OUTPUT_TOKENS["gpt-4o-mini"]
      
      input_cost = (@input_tokens / 1000.0) * input_cost_per_1k
      output_cost = (@output_tokens / 1000.0) * output_cost_per_1k
      
      (input_cost + output_cost).round(4)
    end
  end
end
