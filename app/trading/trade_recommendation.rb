# frozen_string_literal: true

module Trading
  # Final immutable contract for trade execution
  # Built ONLY from TradeFacts + TradeIntent
  # This replaces loose trade_plan hashes everywhere downstream
  # Frozen/immutable and serializable
  class TradeRecommendation
    attr_reader :facts, :intent
    attr_reader :entry_price, :stop_loss, :target_prices
    attr_reader :risk_reward, :risk_per_share, :risk_amount
    attr_reader :confidence_score
    attr_reader :quantity
    attr_reader :invalidation_conditions
    attr_reader :entry_conditions
    attr_reader :reasoning
    attr_reader :lifecycle
    attr_reader :created_at

    def initialize(facts:, intent:, quantity: 0, risk_amount: 0.0, confidence_score: nil, invalidation_conditions: [], entry_conditions: {}, reasoning: [], lifecycle: nil, created_at: Time.current)
      @facts = facts
      @intent = intent
      @entry_price = intent.proposed_entry
      @stop_loss = intent.proposed_sl
      @target_prices = intent.proposed_targets
      @risk_reward = intent.expected_rr
      @risk_per_share = intent.risk_per_share
      @risk_amount = risk_amount.to_f
      @confidence_score = confidence_score || facts.screener_score
      @quantity = quantity.to_i
      @invalidation_conditions = invalidation_conditions.freeze
      @entry_conditions = entry_conditions.freeze
      @reasoning = reasoning.freeze
      @lifecycle = lifecycle || TradeLifecycle.new(initial_state: TradeLifecycle::PROPOSED, created_at: created_at)
      @created_at = created_at
    end

    # Convenience accessors
    def symbol
      facts.symbol
    end

    def instrument_id
      facts.instrument_id
    end

    def timeframe
      facts.timeframe
    end

    def bias
      intent.bias
    end

    def long?
      intent.long?
    end

    def short?
      intent.short?
    end

    def avoid?
      intent.avoid?
    end

    def valid?
      !avoid? &&
        entry_price&.positive? &&
        stop_loss&.positive? &&
        risk_reward >= 2.0 &&
        confidence_score >= 60.0 &&
        quantity.positive?
    end

    def to_hash
      {
        symbol: symbol,
        instrument_id: instrument_id,
        timeframe: timeframe,
        bias: bias,
        entry_price: entry_price,
        stop_loss: stop_loss,
        target_prices: target_prices,
        risk_reward: risk_reward,
        risk_per_share: risk_per_share,
        risk_amount: risk_amount,
        confidence_score: confidence_score,
        quantity: quantity,
        invalidation_conditions: invalidation_conditions,
        entry_conditions: entry_conditions,
        reasoning: reasoning,
        lifecycle: lifecycle.to_hash,
        facts: facts.to_hash,
        intent: intent.to_hash,
        created_at: created_at.iso8601,
      }
    end

    def to_json(*args)
      to_hash.to_json(*args)
    end
  end
end
