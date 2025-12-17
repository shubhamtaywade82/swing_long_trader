# frozen_string_literal: true

module Trading
  module DecisionEngine
    # Main Decision Engine orchestrator
    # Runs all validation layers in sequence
    # Pure function - no database writes, no LLM, no WebSocket
    class Engine < ApplicationService
      def self.call(trade_recommendation:, portfolio: nil, system_context: nil, config: {})
        new(
          trade_recommendation: trade_recommendation,
          portfolio: portfolio,
          system_context: system_context,
          config: config,
        ).call
      end

      def initialize(trade_recommendation:, portfolio: nil, system_context: nil, config: {})
        @recommendation = trade_recommendation
        @portfolio = portfolio
        @system_context = system_context || build_system_context
        @config = load_config.merge(config)
      end

      def call
        # Check if Decision Engine is enabled
        return disabled_response unless enabled?

        # Step 1: Validate structure
        validation = Validator.call(@recommendation, config: @config)
        return build_response(validation, "validator") unless validation[:approved]

        # Step 2: Enforce risk rules
        risk_check = RiskRules.call(
          @recommendation,
          portfolio: @portfolio,
          system_context: @system_context,
          config: @config,
        )
        return build_response(risk_check, "risk_rules") unless risk_check[:approved]

        # Step 3: Filter weak setups
        setup_check = SetupQuality.call(@recommendation, config: @config)
        return build_response(setup_check, "setup_quality") unless setup_check[:approved]

        # Step 4: Check portfolio constraints
        portfolio_check = PortfolioConstraints.call(
          @recommendation,
          portfolio: @portfolio,
          config: @config,
        )
        return build_response(portfolio_check, "portfolio_constraints") unless portfolio_check[:approved]

        # All checks passed
        # Optional: LLM review (advisory only, never blocks)
        llm_review = nil
        if Trading::Config.llm_enabled?
          llm_review = perform_llm_review
        end

        # Transition lifecycle to APPROVED
        @recommendation.lifecycle.approve!(reason: "Approved by Decision Engine")

        decision_result = {
          approved: true,
          recommendation: @recommendation,
          decision_path: [
            validation[:reason],
            risk_check[:reason],
            setup_check[:reason],
            portfolio_check[:reason],
          ],
          llm_review: llm_review,
          system_context: @system_context.to_hash,
          checked_at: Time.current,
        }

        # Log decision to audit log
        log_decision(decision_result, llm_review: llm_review)

        decision_result
      end

      private

      def build_system_context
        if @portfolio
          Trading::SystemContext.from_portfolio(@portfolio)
        else
          Trading::SystemContext.empty
        end
      end

      def enabled?
        Trading::Config.decision_engine_enabled?
      end

      def load_config
        {
          min_risk_reward: Trading::Config.config_value("trading", "decision_engine", "min_risk_reward") || 2.0,
          min_confidence: Trading::Config.config_value("trading", "decision_engine", "min_confidence") || 60.0,
          max_volatility_pct: Trading::Config.config_value("trading", "decision_engine", "max_volatility_pct") || 8.0,
          max_positions_per_symbol: Trading::Config.config_value("trading", "decision_engine", "max_positions_per_symbol") || 1,
          max_daily_risk_pct: Trading::Config.config_value("trading", "decision_engine", "max_daily_risk_pct") || 2.0,
        }
      end

      def build_response(check_result, stage)
        {
          approved: false,
          recommendation: @recommendation,
          reason: check_result[:reason],
          stage: stage,
          errors: check_result[:errors] || [],
          decision_path: [check_result[:reason]],
          checked_at: Time.current,
        }
      end

      def disabled_response
        {
          approved: true,
          recommendation: @recommendation,
          reason: "Decision Engine disabled (feature flag)",
          stage: "disabled",
          decision_path: ["Decision Engine disabled"],
          checked_at: Time.current,
        }
      end

      def perform_llm_review
        LLM::ReviewService.call(@recommendation)
      rescue StandardError => e
        Rails.logger.error("[Trading::DecisionEngine::Engine] LLM review failed: #{e.message}")
        nil
      end

      def log_decision(decision_result, llm_review: nil)
        return unless Trading::Config.dto_enabled?

        system_context = @system_context || Trading::SystemContext.empty

        audit_log = Trading::AuditLog.new(
          trade_recommendation: @recommendation,
          system_context: system_context,
        )

        audit_log.log_decision(decision_result, system_context: system_context, llm_review: llm_review)
      rescue StandardError => e
        Rails.logger.error("[Trading::DecisionEngine::Engine] Audit log failed: #{e.message}")
        # Don't fail decision if audit log fails
      end
    end
  end
end
