# frozen_string_literal: true

module Trading
  # Represents what we want to do (proposed action)
  # Contains entry/SL/TP but NOT quantity (that's execution-level)
  # No risk calculations here - just intent
  class TradeIntent
    attr_reader :bias  # :long, :short, :avoid
    attr_reader :proposed_entry
    attr_reader :proposed_sl
    attr_reader :proposed_targets  # Array of [price, probability] tuples
    attr_reader :expected_rr
    attr_reader :sizing_hint  # NOT quantity - just a hint (e.g., "small", "medium", "large")
    attr_reader :strategy_key  # Identifier for the strategy that generated this intent

    def initialize(
      bias:,
      proposed_entry:,
      proposed_sl:,
      proposed_targets: [],
      expected_rr: 0.0,
      sizing_hint: "medium",
      strategy_key: nil
    )
      @bias = bias.to_sym
      @proposed_entry = proposed_entry.to_f
      @proposed_sl = proposed_sl.to_f
      @proposed_targets = proposed_targets.freeze
      @expected_rr = expected_rr.to_f
      @sizing_hint = sizing_hint.to_s
      @strategy_key = strategy_key
    end

    def long?
      bias == :long
    end

    def short?
      bias == :short
    end

    def avoid?
      bias == :avoid
    end

    def risk_per_share
      return 0.0 if proposed_entry.zero? || proposed_sl.zero?

      (proposed_entry - proposed_sl).abs
    end

    def reward_per_share
      return 0.0 if proposed_targets.empty?

      primary_target = proposed_targets.first
      return 0.0 unless primary_target.is_a?(Array) && primary_target.size >= 1

      target_price = primary_target[0].to_f
      (target_price - proposed_entry).abs
    end

    def to_hash
      {
        bias: bias,
        proposed_entry: proposed_entry,
        proposed_sl: proposed_sl,
        proposed_targets: proposed_targets,
        expected_rr: expected_rr,
        sizing_hint: sizing_hint,
        strategy_key: strategy_key,
        risk_per_share: risk_per_share,
        reward_per_share: reward_per_share,
      }
    end
  end
end
