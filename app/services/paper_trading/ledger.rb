# frozen_string_literal: true

module PaperTrading
  # Manages ledger entries for paper trading portfolio
  class Ledger < ApplicationService
    def self.credit(portfolio:, amount:, reason:, description: nil, position: nil, meta: {})
      new(
        portfolio: portfolio,
        amount: amount,
        transaction_type: "credit",
        reason: reason,
        description: description,
        position: position,
        meta: meta,
      ).record
    end

    def self.debit(portfolio:, amount:, reason:, description: nil, position: nil, meta: {})
      new(
        portfolio: portfolio,
        amount: amount,
        transaction_type: "debit",
        reason: reason,
        description: description,
        position: position,
        meta: meta,
      ).record
    end

    def initialize(portfolio:, amount:, transaction_type:, reason:, description: nil, position: nil, meta: {})
      @portfolio = portfolio
      @amount = amount.to_f
      @transaction_type = transaction_type
      @reason = reason
      @description = description
      @position = position
      @meta = meta
    end

    def record
      ledger_entry = PaperLedger.create!(
        paper_portfolio: @portfolio,
        paper_position: @position,
        amount: @amount,
        transaction_type: @transaction_type,
        reason: @reason,
        description: @description,
        meta: @meta.to_json,
      )

      # Update portfolio capital
      update_portfolio_capital

      log_info("Ledger #{@transaction_type}: ₹#{@amount} (#{@reason})")
      ledger_entry
    rescue StandardError => e
      log_error("Failed to record ledger entry: #{e.message}")
      raise
    end

    private

    def update_portfolio_capital
      if @transaction_type == "credit"
        @portfolio.increment!(:capital, @amount)
      else
        @portfolio.decrement!(:capital, @amount)
      end

      @portfolio.update_equity!
    end
  end
end
