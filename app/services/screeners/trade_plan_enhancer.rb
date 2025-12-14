# frozen_string_literal: true

module Screeners
  # Enhances trade plans with portfolio-aware quantity calculations
  # Called after portfolio is available (Layer 2+)
  class TradePlanEnhancer < ApplicationService
    def self.call(candidates:, portfolio: nil)
      new(candidates: candidates, portfolio: portfolio).call
    end

    def initialize(candidates:, portfolio: nil) # rubocop:disable Lint/MissingSuper
      @candidates = candidates
      @portfolio = portfolio
    end

    def call
      return @candidates unless @portfolio

      @candidates.map do |candidate|
        next candidate unless candidate[:trade_plan] && candidate[:setup_status] == SetupDetector::READY

        # Recalculate quantity with actual portfolio capital
        enhanced_plan = enhance_trade_plan(candidate[:trade_plan], candidate)

        if enhanced_plan
          candidate[:trade_plan] = enhanced_plan
          # Update recommendation with accurate quantity
          candidate[:recommendation] = build_actionable_recommendation(enhanced_plan)
        end

        candidate
      end
    end

    private

    def enhance_trade_plan(trade_plan, candidate)
      entry_price = trade_plan[:entry_price]
      risk_per_share = trade_plan[:risk_per_share]

      return nil unless entry_price && risk_per_share

      # Get available capital
      available_capital = if @portfolio.is_a?(CapitalAllocationPortfolio)
                            @portfolio.available_swing_capital || @portfolio.swing_capital || 0
                          elsif @portfolio.respond_to?(:available_capital)
                            @portfolio.available_capital || 0
                          else
                            0
                          end

      return trade_plan if available_capital <= 0

      # Calculate risk per trade (0.75% of capital)
      risk_per_trade = available_capital * 0.0075

      # Calculate quantity based on risk
      quantity_by_risk = (risk_per_trade / risk_per_share).floor

      # Also limit by max position size (12% of capital)
      max_capital_pct = 12.0
      max_position_value = available_capital * (max_capital_pct / 100.0)
      quantity_by_capital = (max_position_value / entry_price).floor

      # Use the smaller of the two (most conservative)
      quantity = [quantity_by_risk, quantity_by_capital].min
      quantity = [quantity, 1].max # Ensure minimum of 1

      capital_used = (quantity * entry_price).round(2)
      risk_amount = (quantity * risk_per_share).round(2)

      trade_plan.merge(
        quantity: quantity,
        capital_used: capital_used,
        risk_amount: risk_amount,
        max_capital_pct: ((capital_used / available_capital) * 100).round(2),
      )
    end

    def build_actionable_recommendation(trade_plan)
      "BUY #{trade_plan[:entry_zone]}, SL #{trade_plan[:stop_loss]}, TP #{trade_plan[:take_profit]}, " \
        "Qty #{trade_plan[:quantity]}, Risk ₹#{trade_plan[:risk_amount]}, RR #{trade_plan[:risk_reward]}R"
    end
  end
end
