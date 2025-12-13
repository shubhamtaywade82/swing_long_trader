# frozen_string_literal: true

module Swing
  class PositionSizer < ApplicationService
    def initialize(portfolio:, entry_price:, stop_loss:, instrument:)
      @portfolio = portfolio
      @entry_price = entry_price.to_f
      @stop_loss = stop_loss.to_f
      @instrument = instrument
      @risk_config = portfolio.swing_risk_config
    end

    def call
      return failure("Invalid entry price or stop loss") if @entry_price <= 0 || @stop_loss <= 0
      return failure("Stop loss must be different from entry price") if @entry_price == @stop_loss

      risk_per_share = calculate_risk_per_share
      return failure("Invalid risk per share") if risk_per_share <= 0

      risk_amount = @risk_config.risk_per_trade_amount
      raw_quantity = calculate_raw_quantity(risk_amount, risk_per_share)
      return failure("Calculated quantity is zero") if raw_quantity <= 0

      final_quantity = apply_exposure_cap(raw_quantity)
      return failure("Final quantity is zero after exposure cap") if final_quantity <= 0

      capital_required = final_quantity * @entry_price
      available_capital = @portfolio.available_swing_capital

      if capital_required > available_capital
        # Recalculate with available capital
        final_quantity = (available_capital / @entry_price).floor
        return failure("Insufficient swing capital") if final_quantity <= 0
      end

      actual_risk = final_quantity * risk_per_share
      actual_risk_pct = (@portfolio.total_equity > 0) ? (actual_risk / @portfolio.total_equity * 100).round(2) : 0

      success(
        quantity: final_quantity,
        capital_required: final_quantity * @entry_price,
        risk_amount: actual_risk,
        risk_percentage: actual_risk_pct,
        risk_per_share: risk_per_share,
      )
    end

    private

    def calculate_risk_per_share
      (@entry_price - @stop_loss).abs
    end

    def calculate_raw_quantity(risk_amount, risk_per_share)
      (risk_amount / risk_per_share).floor
    end

    def apply_exposure_cap(raw_quantity)
      max_exposure_amount = @risk_config.max_position_exposure_amount
      max_quantity_by_exposure = (max_exposure_amount / @entry_price).floor

      [raw_quantity, max_quantity_by_exposure].min
    end

    def success(data)
      { success: true, **data }
    end

    def failure(message)
      { success: false, error: message }
    end
  end
end
