# frozen_string_literal: true

module Trading
  # Main orchestrator that wires ScreenerResult → Decision Engine → Executor
  # Integration point from existing screeners to new Trading Agent system
  class Orchestrator < ApplicationService
    def self.process_screener_result(screener_result, portfolio: nil, mode: nil, dry_run: false)
      new(
        screener_result: screener_result,
        portfolio: portfolio,
        mode: mode,
        dry_run: dry_run,
      ).process
    end

    def initialize(screener_result:, portfolio: nil, mode: nil, dry_run: false)
      @screener_result = screener_result
      @portfolio = portfolio
      @mode = mode || Trading::Config.current_mode
      @dry_run = dry_run
    end

    def process
      # Check feature flags
      unless Trading::Config.dto_enabled?
        return {
          success: false,
          error: "DTO system not enabled (set dto_enabled: true)",
          stage: "feature_flag",
        }
      end

      # Step 1: Convert ScreenerResult → TradeRecommendation
      recommendation = convert_to_recommendation
      unless recommendation
        return {
          success: false,
          error: "Failed to convert ScreenerResult to TradeRecommendation",
          stage: "conversion",
        }
      end

      # Step 2: Run Decision Engine
      decision_result = run_decision_engine(recommendation)
      unless decision_result[:approved]
        return {
          success: false,
          error: "Decision Engine rejected: #{decision_result[:reason]}",
          stage: "decision_engine",
          decision_result: decision_result,
          recommendation: recommendation,
        }
      end

      # Step 3: Execute (if mode allows)
      if mode_allows_execution?
        execution_result = execute_trade(recommendation, decision_result)
        {
          success: execution_result[:success],
          recommendation: recommendation,
          decision_result: decision_result,
          execution_result: execution_result,
          stage: "execution",
        }
      else
        # Advisory mode - return recommendation only
        {
          success: true,
          recommendation: recommendation,
          decision_result: decision_result,
          execution_result: nil,
          stage: "advisory",
          message: "Advisory mode - recommendation generated, no execution",
        }
      end
    end

    private

    def convert_to_recommendation
      Trading::Adapters::ScreenerResultToRecommendation.call(@screener_result, portfolio: @portfolio)
    end

    def run_decision_engine(recommendation)
      Trading::DecisionEngine::Engine.call(
        trade_recommendation: recommendation,
        portfolio: @portfolio,
      )
    end

    def execute_trade(recommendation, decision_result)
      Trading::Executor.execute(
        trade_recommendation: recommendation,
        decision_result: decision_result,
        portfolio: @portfolio,
        mode: @mode,
        dry_run: @dry_run,
      )
    end

    def mode_allows_execution?
      @mode != "advisory"
    end
  end
end
