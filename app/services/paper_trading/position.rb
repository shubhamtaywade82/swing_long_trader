# frozen_string_literal: true

module PaperTrading
  # Manages paper trading positions
  class Position < ApplicationService
    def self.create(portfolio:, instrument:, signal:)
      new(portfolio: portfolio, instrument: instrument, signal: signal).create!
    end

    def initialize(portfolio:, instrument:, signal:)
      @portfolio = portfolio
      @instrument = instrument
      @signal = signal
    end

    def create
      # Calculate position value
      entry_price = @signal[:entry_price]
      quantity = @signal[:qty]
      position_value = entry_price * quantity

      # Reserve capital (don't debit - capital stays same, just reserved)
      reserve_capital(position_value)

      # Create position in unified positions table with trading_mode='paper'
      position = ::Position.create!(
        paper_portfolio: @portfolio, # For backward compatibility
        instrument: @instrument,
        trading_mode: "paper",
        symbol: @instrument.symbol_name,
        direction: @signal[:direction].to_s,
        entry_price: entry_price,
        current_price: entry_price,
        quantity: quantity,
        stop_loss: @signal[:sl],
        take_profit: @signal[:tp],
        status: "open",
        opened_at: Time.current,
        metadata: @signal[:metadata]&.to_json || {}.to_json,
      )

      # Record ledger entry (for audit trail only - doesn't change capital)
      PaperLedger.create!(
        paper_portfolio: @portfolio,
        paper_position: position,
        amount: position_value,
        transaction_type: "debit",
        reason: "trade_entry",
        description: "Entry: #{@instrument.symbol_name} #{@signal[:direction].to_s.upcase} @ ₹#{entry_price}",
        meta: {
          symbol: @instrument.symbol_name,
          direction: @signal[:direction],
          entry_price: entry_price,
          quantity: quantity,
        }.to_json,
      )

      log_info("Created paper position: #{@instrument.symbol_name} #{@signal[:direction].to_s.upcase} #{quantity} @ ₹#{entry_price}")
      position
    rescue StandardError => e
      log_error("Failed to create position: #{e.message}")
      raise
    end

    private

    def reserve_capital(amount)
      @portfolio.increment!(:reserved_capital, amount)
      @portfolio.update_equity!
    end
  end
end
