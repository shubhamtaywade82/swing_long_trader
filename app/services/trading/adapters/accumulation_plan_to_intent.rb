# frozen_string_literal: true

module Trading
  module Adapters
    # Converts accumulation_plan hash → TradeIntent (for long-term trading)
    # Similar to TradePlanToIntent but handles accumulation format
    class AccumulationPlanToIntent
      def self.call(accumulation_plan_hash, strategy_key: nil)
        new(accumulation_plan_hash, strategy_key: strategy_key).call
      end

      def initialize(accumulation_plan_hash, strategy_key: nil)
        @accumulation_plan = accumulation_plan_hash || {}
        @strategy_key = strategy_key
      end

      def call
        return nil unless @accumulation_plan.is_a?(Hash)
        return nil unless @accumulation_plan[:buy_zone] || @accumulation_plan[:entry_price]

        # For accumulation, bias is always :long
        bias = :long

        # Extract entry zone (use midpoint if range, or single price)
        entry = extract_entry_price

        # Extract invalid level as stop loss
        sl = extract_stop_loss(entry)

        # Extract targets (long-term horizon)
        targets = extract_targets(entry)

        # RR calculation for accumulation (typically lower, but longer horizon)
        expected_rr = @accumulation_plan[:expected_rr]&.to_f || 1.5 # Conservative default

        # Sizing hint from allocation
        sizing_hint = determine_sizing_hint

        Trading::TradeIntent.new(
          bias: bias,
          proposed_entry: entry,
          proposed_sl: sl,
          proposed_targets: targets,
          expected_rr: expected_rr,
          sizing_hint: sizing_hint,
          strategy_key: @strategy_key || "longterm_trading",
        )
      end

      private

      def extract_entry_price
        # Handle buy_zone (could be range like "100.0 - 105.0" or single price)
        if @accumulation_plan[:buy_zone]
          zone = @accumulation_plan[:buy_zone].to_s
          # Try to parse range
          if zone.include?(" - ")
            parts = zone.split(" - ").map(&:strip)
            # Use midpoint
            (parts[0].to_f + parts[1].to_f) / 2.0
          else
            zone.to_f
          end
        elsif @accumulation_plan[:entry_price]
          @accumulation_plan[:entry_price].to_f
        else
          0.0
        end
      end

      def extract_stop_loss(entry)
        # Use invalid_level as stop loss
        if @accumulation_plan[:invalid_level]&.positive?
          @accumulation_plan[:invalid_level].to_f
        else
          # Fallback: 20% below entry (conservative for long-term)
          entry * 0.8
        end
      end

      def extract_targets(entry)
        targets = []

        # Long-term targets are typically further out
        # Could extract from accumulation_plan if available
        # For now, use a conservative target (50% above entry)
        if entry.positive?
          target = entry * 1.5
          targets << [target, 0.6] # 60% probability for long-term
        end

        targets
      end

      def determine_sizing_hint
        # Map from allocation_pct
        if @accumulation_plan[:allocation_pct]
          pct = @accumulation_plan[:allocation_pct].to_f
          if pct >= 10.0
            "large"
          elsif pct >= 5.0
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
