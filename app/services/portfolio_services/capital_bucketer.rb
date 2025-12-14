# frozen_string_literal: true

module PortfolioServices
  class CapitalBucketer < ApplicationService
    EARLY_STAGE_THRESHOLD = 300_000.0 # ₹3L
    GROWTH_STAGE_THRESHOLD = 500_000.0 # ₹5L

    EARLY_STAGE_ALLOCATION = {
      swing: 80.0,
      long_term: 0.0,
      cash: 20.0,
    }.freeze

    GROWTH_STAGE_ALLOCATION = {
      swing: 70.0,
      long_term: 20.0,
      cash: 10.0,
    }.freeze

    MATURE_STAGE_ALLOCATION = {
      swing: 60.0,
      long_term: 30.0,
      cash: 10.0,
    }.freeze

    def initialize(portfolio:)
      @portfolio = portfolio
      @bucket = portfolio.capital_bucket || portfolio.create_capital_bucket!
    end

    def call
      allocation = determine_allocation
      apply_allocation(allocation)
    end

    def determine_allocation
      total_equity = @portfolio.total_equity

      if total_equity < EARLY_STAGE_THRESHOLD
        EARLY_STAGE_ALLOCATION.dup
      elsif total_equity < GROWTH_STAGE_THRESHOLD
        GROWTH_STAGE_ALLOCATION.dup
      else
        MATURE_STAGE_ALLOCATION.dup
      end
    end

    def apply_allocation(allocation)
      total = @portfolio.total_equity

      # Calculate target amounts
      target_swing = (total * allocation[:swing] / 100.0).round(2)
      target_long_term = (total * allocation[:long_term] / 100.0).round(2)
      target_cash = (total * allocation[:cash] / 100.0).round(2)

      # Get current exposure
      current_swing_exposure = @portfolio.total_swing_exposure
      current_long_term_value = @portfolio.total_long_term_value

      # Adjust for existing positions - can't reduce below current exposure
      final_swing_capital = [target_swing, current_swing_exposure].max
      final_long_term_capital = [target_long_term, current_long_term_value].max

      # Recalculate cash
      final_cash = total - final_swing_capital - final_long_term_capital

      # Ensure cash doesn't go negative
      if final_cash.negative?
        excess = final_cash.abs
        # Reduce swing capital first, then long-term
        if final_swing_capital > current_swing_exposure
          reduction = [excess, (final_swing_capital - current_swing_exposure)].min
          final_swing_capital -= reduction
          excess -= reduction
        end

        if excess.positive? && final_long_term_capital > current_long_term_value
          reduction = [excess, (final_long_term_capital - current_long_term_value)].min
          final_long_term_capital -= reduction
        end

        final_cash = total - final_swing_capital - final_long_term_capital
      end

      # Update bucket configuration
      @bucket.update!(
        swing_pct: allocation[:swing],
        long_term_pct: allocation[:long_term],
        cash_pct: allocation[:cash],
        threshold_3l: EARLY_STAGE_THRESHOLD,
        threshold_5l: GROWTH_STAGE_THRESHOLD,
      )

      # Update portfolio capital buckets
      @portfolio.update!(
        swing_capital: final_swing_capital,
        long_term_capital: final_long_term_capital,
        available_cash: final_cash,
      )

      # Record in ledger
      @portfolio.ledger_entries.create!(
        amount: total,
        reason: "capital_rebalance",
        entry_type: "credit",
        metadata: {
          phase: phase_for_equity(total),
          allocation: allocation,
          swing_capital: final_swing_capital,
          long_term_capital: final_long_term_capital,
          cash: final_cash,
        }.to_json,
      )

      {
        success: true,
        phase: phase_for_equity(total),
        allocation: allocation,
        swing_capital: final_swing_capital,
        long_term_capital: final_long_term_capital,
        cash: final_cash,
      }
    end

    def phase_for_equity(total)
      return "early" if total < EARLY_STAGE_THRESHOLD
      return "growth" if total < GROWTH_STAGE_THRESHOLD

      "mature"
    end
  end
end
