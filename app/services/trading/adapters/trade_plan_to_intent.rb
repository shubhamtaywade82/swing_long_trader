# frozen_string_literal: true

module Trading
  module Adapters
    # Converts trade_plan hash → TradeIntent
    # Preserves existing behavior - NO new logic
    class TradePlanToIntent
      def self.call(trade_plan_hash, strategy_key: nil)
        new(trade_plan_hash, strategy_key: strategy_key).call
      end

      def initialize(trade_plan_hash, strategy_key: nil)
        @trade_plan = trade_plan_hash || {}
        @strategy_key = strategy_key
      end

      def call
        return nil unless @trade_plan.is_a?(Hash)
        return nil unless @trade_plan[:entry_price]&.positive?
        return nil unless @trade_plan[:stop_loss]&.positive?

        # Determine bias (default to long for current system)
        bias = determine_bias

        # Extract entry and stop loss
        entry = @trade_plan[:entry_price].to_f
        sl = @trade_plan[:stop_loss].to_f

        # Extract targets
        targets = extract_targets(entry)

        # Calculate expected RR (from trade_plan if available)
        expected_rr = @trade_plan[:risk_reward]&.to_f || calculate_rr(entry, sl, targets)

        # Determine sizing hint from trade_plan
        sizing_hint = determine_sizing_hint

        Trading::TradeIntent.new(
          bias: bias,
          proposed_entry: entry,
          proposed_sl: sl,
          proposed_targets: targets,
          expected_rr: expected_rr,
          sizing_hint: sizing_hint,
          strategy_key: @strategy_key || "swing_trading",
        )
      end

      private

      def determine_bias
        # Current system is long-only
        # Could be extended to check direction from trade_plan if available
        :long
      end

      def extract_targets(entry)
        targets = []

        # Primary target from take_profit
        if @trade_plan[:take_profit]&.positive?
          tp = @trade_plan[:take_profit].to_f
          # Default probability 0.7 (70%) for primary target
          targets << [tp, 0.7]
        end

        # Additional targets could be extracted here if available
        # For now, just primary target

        targets
      end

      def calculate_rr(entry, sl, targets)
        return 0.0 if entry.zero? || sl.zero?

        risk = (entry - sl).abs
        return 0.0 if risk.zero?

        # Use primary target if available
        if targets.any? && targets.first.is_a?(Array) && targets.first.size >= 1
          reward = (targets.first[0].to_f - entry).abs
          return (reward / risk).round(2) if reward.positive?
        end

        # Fallback: use expected_rr from trade_plan if available
        @trade_plan[:risk_reward]&.to_f || 0.0
      end

      def determine_sizing_hint
        # Map from trade_plan metadata if available
        # Could use capital_used, max_capital_pct, or risk_amount
        if @trade_plan[:max_capital_pct]
          pct = @trade_plan[:max_capital_pct].to_f
          if pct >= 10.0
            "large"
          elsif pct >= 5.0
            "medium"
          else
            "small"
          end
        elsif @trade_plan[:risk_amount]
          risk = @trade_plan[:risk_amount].to_f
          # Rough heuristic: assume 100k capital
          risk_pct = (risk / 100_000.0 * 100.0)
          if risk_pct >= 1.0
            "large"
          elsif risk_pct >= 0.5
            "medium"
          else
            "small"
          end
        else
          "medium" # Default
        end
      end
    end
  end
end
