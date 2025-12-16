# frozen_string_literal: true

module Trading
  module Adapters
    # Combines ScreenerResult → TradeFacts + TradePlan → TradeIntent → TradeRecommendation
    # This is the main adapter that wires everything together
    class ScreenerResultToRecommendation
      def self.call(screener_result, portfolio: nil)
        new(screener_result, portfolio: portfolio).call
      end

      def initialize(screener_result, portfolio: nil)
        @screener_result = screener_result
        @portfolio = portfolio
      end

      def call
        return nil unless @screener_result
        return nil unless feature_flag_enabled?

        # Step 1: Extract facts
        facts = ScreenerResultToFacts.call(@screener_result)
        return nil unless facts

        # Step 2: Extract intent from trade_plan or accumulation_plan
        intent = extract_intent
        return nil unless intent

        # Step 3: Extract quantity and risk_amount from trade_plan
        quantity = extract_quantity
        risk_amount = extract_risk_amount

        # Step 4: Extract invalidation conditions and entry conditions
        invalidation_conditions = extract_invalidation_conditions
        entry_conditions = extract_entry_conditions

        # Step 5: Build reasoning
        reasoning = build_reasoning(facts, intent)

        # Step 6: Build TradeRecommendation
        Trading::TradeRecommendation.new(
          facts: facts,
          intent: intent,
          quantity: quantity,
          risk_amount: risk_amount,
          confidence_score: facts.screener_score,
          invalidation_conditions: invalidation_conditions,
          entry_conditions: entry_conditions,
          reasoning: reasoning,
          created_at: @screener_result.analyzed_at || Time.current,
        )
      end

      private

      def feature_flag_enabled?
        Trading::Config.dto_enabled?
      end

      def extract_intent
        metadata = @screener_result.metadata_hash || {}

        # Try trade_plan first (swing)
        if metadata["trade_plan"] || metadata[:trade_plan]
          trade_plan = metadata["trade_plan"] || metadata[:trade_plan]
          TradePlanToIntent.call(
            trade_plan,
            strategy_key: "swing_trading",
          )
        # Try accumulation_plan (long-term)
        elsif metadata["accumulation_plan"] || metadata[:accumulation_plan]
          accumulation_plan = metadata["accumulation_plan"] || metadata[:accumulation_plan]
          AccumulationPlanToIntent.call(
            accumulation_plan,
            strategy_key: "longterm_trading",
          )
        else
          nil
        end
      end

      def extract_quantity
        metadata = @screener_result.metadata_hash || {}
        trade_plan = metadata["trade_plan"] || metadata[:trade_plan] || {}
        trade_plan["quantity"] || trade_plan[:quantity] || 0
      end

      def extract_risk_amount
        metadata = @screener_result.metadata_hash || {}
        trade_plan = metadata["trade_plan"] || metadata[:trade_plan] || {}
        (trade_plan["risk_amount"] || trade_plan[:risk_amount] || 0.0).to_f
      end

      def extract_invalidation_conditions
        conditions = []

        metadata = @screener_result.metadata_hash || {}
        invalidate_if = metadata["invalidate_if"] || metadata[:invalidate_if]
        conditions << invalidate_if if invalidate_if.present?

        # Could add more conditions from setup_status, etc.

        conditions.compact
      end

      def extract_entry_conditions
        metadata = @screener_result.metadata_hash || {}
        entry_conditions = metadata["entry_conditions"] || metadata[:entry_conditions] || {}
        entry_conditions.is_a?(Hash) ? entry_conditions : {}
      end

      def build_reasoning(facts, intent)
        reasoning = []

        # Add trend reasoning
        if facts.trend_flags.include?(:bullish)
          reasoning << "Bullish trend confirmed (EMA + Supertrend)"
        end

        if facts.trend_flags.include?(:bearish)
          reasoning << "Bearish trend detected"
        end

        # Add momentum reasoning
        if facts.momentum_flags.include?(:rsi_bullish)
          reasoning << "RSI in bullish zone (50-70)"
        end

        if facts.momentum_flags.include?(:macd_bullish)
          reasoning << "MACD bullish crossover"
        end

        if facts.momentum_flags.include?(:adx_strong)
          reasoning << "Strong trend (ADX > 25)"
        end

        # Add setup status reasoning
        if facts.setup_status == "READY"
          reasoning << "Setup ready for entry"
        elsif facts.setup_status == "WAIT_PULLBACK"
          reasoning << "Waiting for pullback"
        end

        # Add RR reasoning
        if intent.expected_rr >= 3.0
          reasoning << "Excellent risk-reward (#{intent.expected_rr.round(2)}R)"
        elsif intent.expected_rr >= 2.0
          reasoning << "Good risk-reward (#{intent.expected_rr.round(2)}R)"
        end

        reasoning
      end
    end
  end
end
