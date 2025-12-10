# frozen_string_literal: true

module Backtesting
  # Virtual portfolio manager for backtesting
  class Portfolio
    attr_reader :initial_capital, :current_capital, :positions, :closed_positions, :equity_curve

    def initialize(initial_capital:)
      @initial_capital = initial_capital.to_f
      @current_capital = @initial_capital
      @positions = {} # {instrument_id => Position}
      @closed_positions = []
      @equity_curve = [{ date: nil, equity: @initial_capital }]
    end

    def open_position(instrument_id:, entry_date:, entry_price:, quantity:, direction:, stop_loss:, take_profit:)
      cost = entry_price * quantity
      return false if cost > @current_capital

      position = Position.new(
        instrument_id: instrument_id,
        entry_date: entry_date,
        entry_price: entry_price,
        quantity: quantity,
        direction: direction,
        stop_loss: stop_loss,
        take_profit: take_profit
      )

      @positions[instrument_id] = position
      @current_capital -= cost

      true
    end

    def close_position(instrument_id:, exit_date:, exit_price:, exit_reason:)
      position = @positions.delete(instrument_id)
      return false unless position

      position.close(exit_date: exit_date, exit_price: exit_price, exit_reason: exit_reason)
      pnl = position.calculate_pnl
      @current_capital += (position.entry_price * position.quantity) + pnl

      @closed_positions << position
      update_equity_curve(exit_date)

      position
    end

    def update_equity_curve(date)
      open_value = @positions.values.sum { |pos| pos.current_value }
      equity = @current_capital + open_value
      @equity_curve << { date: date, equity: equity }
    end

    def total_return
      return 0 if @initial_capital.zero?

      ((@current_capital - @initial_capital) / @initial_capital * 100).round(2)
    end

    def current_equity
      open_value = @positions.values.sum { |pos| pos.current_value }
      @current_capital + open_value
    end
  end
end

