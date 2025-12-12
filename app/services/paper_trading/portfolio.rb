# frozen_string_literal: true

module PaperTrading
  # Manages paper trading portfolio operations
  class Portfolio < ApplicationService
    DEFAULT_PORTFOLIO_NAME = "default"

    def self.find_or_create_default(initial_capital: 100_000)
      portfolio = PaperPortfolio.find_by(name: DEFAULT_PORTFOLIO_NAME)
      return portfolio if portfolio

      create!(name: DEFAULT_PORTFOLIO_NAME, initial_capital: initial_capital)
    end

    def self.create(name:, initial_capital:)
      new(name: name, initial_capital: initial_capital).create!
    end

    def initialize(name:, initial_capital:)
      @name = name
      @initial_capital = initial_capital
    end

    def create
      portfolio = PaperPortfolio.create!(
        name: @name,
        capital: @initial_capital,
        available_capital: @initial_capital,
        total_equity: @initial_capital,
        peak_equity: @initial_capital,
      )

      # Create initial ledger entry
      PaperTrading::Ledger.credit(
        portfolio: portfolio,
        amount: @initial_capital,
        reason: "initial_capital",
        description: "Initial capital allocation",
      )

      log_info("Created paper portfolio: #{@name} with capital ₹#{@initial_capital}")
      portfolio
    rescue StandardError => e
      log_error("Failed to create portfolio: #{e.message}")
      raise
    end
  end
end
