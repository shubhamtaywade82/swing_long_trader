# frozen_string_literal: true

module Backtesting
  # Virtual portfolio manager for backtesting
  class Portfolio
    attr_reader :initial_capital, :current_capital, :positions, :closed_positions, :equity_curve, :total_commission,
                :total_slippage

    def initialize(initial_capital:, config: nil)
      @initial_capital = initial_capital.to_f
      @current_capital = @initial_capital
      @positions = {} # {instrument_id => Position}
      @closed_positions = []
      @equity_curve = [{ date: nil, equity: @initial_capital }]
      @config = config
      @total_commission = 0.0
      @total_slippage = 0.0
    end

    def open_position(instrument_id:, entry_date:, entry_price:, quantity:, direction:, stop_loss:, take_profit:,
                      trailing_stop_pct: nil, trailing_stop_amount: nil)
      # Apply slippage to entry price
      actual_entry_price = apply_slippage(entry_price, direction)
      slippage_cost = (actual_entry_price - entry_price).abs * quantity
      @total_slippage += slippage_cost

      # Calculate cost with slippage
      cost = actual_entry_price * quantity

      # Apply commission
      commission = calculate_commission(cost)
      @total_commission += commission
      total_cost = cost + commission

      return false if total_cost > @current_capital

      position = Position.new(
        instrument_id: instrument_id,
        entry_date: entry_date,
        entry_price: actual_entry_price, # Store actual price with slippage
        quantity: quantity,
        direction: direction,
        stop_loss: stop_loss,
        take_profit: take_profit,
        trailing_stop_pct: trailing_stop_pct,
        trailing_stop_amount: trailing_stop_amount,
      )

      @positions[instrument_id] = position
      @current_capital -= total_cost

      true
    end

    def close_position(instrument_id:, exit_date:, exit_price:, exit_reason:)
      position = @positions.delete(instrument_id)
      return false unless position

      # Apply slippage to exit price
      actual_exit_price = apply_slippage(exit_price, position.direction == :long ? :short : :long)
      slippage_cost = (actual_exit_price - exit_price).abs * position.quantity
      @total_slippage += slippage_cost

      position.close(exit_date: exit_date, exit_price: actual_exit_price, exit_reason: exit_reason)
      pnl = position.calculate_pnl

      # Calculate proceeds from sale
      proceeds = actual_exit_price * position.quantity

      # Apply commission on exit
      commission = calculate_commission(proceeds)
      @total_commission += commission
      _net_proceeds = proceeds - commission

      # Return capital + P&L (P&L already accounts for entry/exit price difference)
      @current_capital += (position.entry_price * position.quantity) + pnl - commission

      @closed_positions << position
      update_equity_curve(exit_date)

      position
    end

    def update_equity_curve(date, current_prices = {})
      open_value = @positions.values.sum do |pos|
        current_price = current_prices[pos.instrument_id] || pos.entry_price
        pos.current_value(current_price)
      end
      equity = @current_capital + open_value
      @equity_curve << { date: date, equity: equity }
    end

    def total_return
      return 0 if @initial_capital.zero?

      ((@current_capital - @initial_capital) / @initial_capital * 100).round(2)
    end

    def current_equity(current_prices = {})
      open_value = @positions.values.sum do |pos|
        current_price = current_prices[pos.instrument_id] || pos.entry_price
        pos.current_value(current_price)
      end
      @current_capital + open_value
    end

    private

    def apply_slippage(price, direction)
      return price unless @config

      @config.apply_slippage(price, direction)
    end

    def calculate_commission(amount)
      return 0.0 unless @config

      # Commission is typically a percentage of trade value
      # apply_commission returns amount * (1 + rate/100), so we need to extract just the commission
      if @config.commission_rate.zero?
        0.0
      else
        amount * (@config.commission_rate / 100.0)
      end
    end
  end
end
