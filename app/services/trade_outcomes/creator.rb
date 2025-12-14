# frozen_string_literal: true

module TradeOutcomes
  # Creates TradeOutcome records from screener results and actual trades
  class Creator < ApplicationService
    def self.call(screener_run:, candidate:, position: nil, trading_mode: "paper")
      new(
        screener_run: screener_run,
        candidate: candidate,
        position: position,
        trading_mode: trading_mode,
      ).call
    end

    def initialize(screener_run:, candidate:, position: nil, trading_mode: "paper")
      @screener_run = screener_run
      @candidate = candidate
      @position = position
      @trading_mode = trading_mode
    end

    def call
      # Extract entry details from position or candidate
      entry_price = @position&.entry_price || @candidate.dig(:indicators, :latest_close) || @candidate[:ltp]
      quantity = @position&.quantity || calculate_quantity(entry_price)
      entry_time = @position&.created_at || @position&.opened_at || Time.current

      # Extract risk management from position or estimate from candidate
      stop_loss = @position&.stop_loss || estimate_stop_loss(@candidate, entry_price)
      take_profit = @position&.take_profit || estimate_take_profit(@candidate, entry_price, stop_loss)
      risk_per_share = stop_loss ? (entry_price - stop_loss).abs : nil
      risk_amount = risk_per_share ? (risk_per_share * quantity) : nil

      # Extract attribution data from candidate
      tier = @candidate[:tier] || determine_tier_from_candidate(@candidate)
      stage = @candidate[:stage] || "final"

      outcome = TradeOutcome.create!(
        screener_run: @screener_run,
        instrument_id: @candidate[:instrument_id],
        symbol: @candidate[:symbol],
        trading_mode: @trading_mode,
        entry_price: entry_price,
        entry_time: entry_time,
        quantity: quantity,
        stop_loss: stop_loss,
        take_profit: take_profit,
        risk_per_share: risk_per_share,
        risk_amount: risk_amount,
        screener_score: @candidate[:score],
        trade_quality_score: @candidate[:trade_quality_score],
        ai_confidence: @candidate[:ai_confidence],
        tier: tier,
        stage: stage,
        position_id: @position&.id,
        position_type: determine_position_type(@position),
        status: "open",
      )

      {
        success: true,
        outcome: outcome,
      }
    rescue StandardError => e
      Rails.logger.error("[TradeOutcomes::Creator] Failed to create outcome: #{e.message}")
      {
        success: false,
        error: e.message,
      }
    end

    private

    def calculate_quantity(entry_price)
      # Default quantity calculation (can be overridden)
      # This should use portfolio risk management
      return 1 unless entry_price&.positive?

      # Placeholder - should use actual position sizing logic
      1
    end

    def estimate_stop_loss(candidate, entry_price)
      return nil unless entry_price&.positive?

      indicators = candidate[:indicators] || {}
      atr = indicators[:atr]
      ema50 = indicators[:ema50]

      # Use 2 ATR below entry or EMA50, whichever is closer
      if atr
        atr_stop = entry_price - (atr * 2)
        if ema50 && ema50 < entry_price
          [atr_stop, ema50 * 0.98].min
        else
          atr_stop
        end
      elsif ema50 && ema50 < entry_price
        ema50 * 0.98
      else
        entry_price * 0.95 # 5% stop as fallback
      end
    end

    def estimate_take_profit(candidate, entry_price, stop_loss)
      return nil unless entry_price&.positive? && stop_loss&.positive?

      risk = (entry_price - stop_loss).abs
      return nil if risk.zero?

      # Target 2.5R minimum
      entry_price + (risk * 2.5)
    end

    def determine_tier_from_candidate(candidate)
      # Determine tier based on rank or scores
      rank = candidate[:rank]
      return "tier_1" if rank && rank <= 3
      return "tier_2" if rank && rank <= 8
      return "tier_3" if rank

      # Fallback to scores
      ai_confidence = candidate[:ai_confidence]
      return "tier_1" if ai_confidence && ai_confidence >= 8.0
      return "tier_2" if ai_confidence && ai_confidence >= 6.5

      "tier_3"
    end

    def determine_position_type(position)
      return nil unless position

      case position.class.name
      when "SwingPosition"
        "swing_position"
      when "PaperPosition"
        "paper_position"
      else
        position.class.name.underscore
      end
    end
  end
end
