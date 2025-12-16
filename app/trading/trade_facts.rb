# frozen_string_literal: true

module Trading
  # Immutable read-only snapshot of market facts
  # No risk logic, no quantities, no RR calculations
  # Just facts about the instrument and its current state
  class TradeFacts
    attr_reader :symbol, :instrument_id, :timeframe
    attr_reader :indicators_snapshot
    attr_reader :trend_flags, :momentum_flags
    attr_reader :screener_score
    attr_reader :setup_status
    attr_reader :detected_at

    def initialize(
      symbol:,
      instrument_id:,
      timeframe:,
      indicators_snapshot: {},
      trend_flags: [],
      momentum_flags: [],
      screener_score: 0.0,
      setup_status: nil,
      detected_at: Time.current
    )
      @symbol = symbol
      @instrument_id = instrument_id
      @timeframe = timeframe
      @indicators_snapshot = indicators_snapshot.freeze
      @trend_flags = trend_flags.freeze
      @momentum_flags = momentum_flags.freeze
      @screener_score = screener_score.to_f
      @setup_status = setup_status
      @detected_at = detected_at
    end

    def to_hash
      {
        symbol: symbol,
        instrument_id: instrument_id,
        timeframe: timeframe,
        indicators_snapshot: indicators_snapshot,
        trend_flags: trend_flags,
        momentum_flags: momentum_flags,
        screener_score: screener_score,
        setup_status: setup_status,
        detected_at: detected_at.iso8601,
      }
    end

    def bullish?
      trend_flags.include?(:bullish) || trend_flags.include?(:ema_bullish) || trend_flags.include?(:supertrend_bullish)
    end

    def bearish?
      trend_flags.include?(:bearish) || trend_flags.include?(:ema_bearish) || trend_flags.include?(:supertrend_bearish)
    end

    def ready?
      setup_status == "READY"
    end
  end
end
