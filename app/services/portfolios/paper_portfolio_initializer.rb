# frozen_string_literal: true

module Portfolios
  # Initializes or ensures paper CapitalAllocationPortfolio has valid capital
  class PaperPortfolioInitializer < ApplicationService
    DEFAULT_PAPER_CAPITAL = 100_000

    def self.call(initial_capital: nil)
      new(initial_capital: initial_capital).call
    end

    def initialize(initial_capital: nil)
      @initial_capital = initial_capital || DEFAULT_PAPER_CAPITAL
    end

    def call
      # Find or create paper CapitalAllocationPortfolio
      portfolio = CapitalAllocationPortfolio.paper.active.first

      unless portfolio
        portfolio = create_paper_portfolio
      end

      # Ensure capital is allocated
      ensure_capital_allocated(portfolio)

      {
        success: true,
        portfolio: portfolio,
        available_swing_capital: portfolio.available_swing_capital,
        total_equity: portfolio.total_equity,
      }
    rescue StandardError => e
      Rails.logger.error("[Portfolios::PaperPortfolioInitializer] Failed: #{e.message}")
      {
        success: false,
        error: e.message,
      }
    end

    private

    def create_paper_portfolio
      portfolio = CapitalAllocationPortfolio.create!(
        name: "Paper Trading Portfolio",
        mode: "paper",
        total_equity: @initial_capital,
        available_cash: @initial_capital,
        swing_capital: 0, # Will be allocated by rebalance (after_create callback)
        long_term_capital: 0,
        realized_pnl: 0,
        unrealized_pnl: 0,
        max_drawdown: 0,
        peak_equity: @initial_capital,
      )

      # Ensure capital is allocated (rebalance will be called by after_create, but ensure it happened)
      portfolio.reload
      if portfolio.swing_capital.zero? && portfolio.total_equity.positive?
        portfolio.rebalance_capital!
      end

      Rails.logger.info(
        "[Portfolios::PaperPortfolioInitializer] Created paper portfolio with capital ₹#{@initial_capital}, " \
        "swing_capital: ₹#{portfolio.swing_capital}, available_swing_capital: ₹#{portfolio.available_swing_capital}"
      )
      portfolio
    end

    def ensure_capital_allocated(portfolio)
      # If total_equity is 0 or very low, initialize it
      if portfolio.total_equity.zero? || portfolio.total_equity < 1000
        Rails.logger.info(
          "[Portfolios::PaperPortfolioInitializer] Portfolio has low/zero equity " \
          "(#{portfolio.total_equity}), initializing with ₹#{@initial_capital}"
        )
        
        portfolio.update!(
          total_equity: @initial_capital,
          available_cash: @initial_capital,
          peak_equity: @initial_capital,
        )
      end

      # Rebalance to allocate swing_capital if needed
      if portfolio.swing_capital.zero? && portfolio.total_equity.positive?
        Rails.logger.info(
          "[Portfolios::PaperPortfolioInitializer] Allocating swing capital " \
          "(total_equity: ₹#{portfolio.total_equity})"
        )
        portfolio.rebalance_capital!
        portfolio.reload
      end

      # Ensure available_swing_capital is positive
      if portfolio.available_swing_capital <= 0 && portfolio.total_equity.positive?
        Rails.logger.warn(
          "[Portfolios::PaperPortfolioInitializer] Available swing capital is still 0 " \
          "(swing_capital: ₹#{portfolio.swing_capital}, exposure: ₹#{portfolio.total_swing_exposure}), " \
          "rebalancing again"
        )
        portfolio.rebalance_capital!
        portfolio.reload
      end

      Rails.logger.info(
        "[Portfolios::PaperPortfolioInitializer] Portfolio initialized: " \
        "total_equity: ₹#{portfolio.total_equity}, " \
        "swing_capital: ₹#{portfolio.swing_capital}, " \
        "available_swing_capital: ₹#{portfolio.available_swing_capital}"
      )
    end
  end
end
