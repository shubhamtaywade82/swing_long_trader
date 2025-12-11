# frozen_string_literal: true

module Backtesting
  # Virtual position tracker for backtesting
  class Position
    attr_reader :instrument_id, :entry_date, :entry_price, :quantity, :direction, :stop_loss, :take_profit
    attr_accessor :exit_date, :exit_price, :exit_reason, :trailing_stop_pct, :trailing_stop_amount

    def initialize(instrument_id:, entry_date:, entry_price:, quantity:, direction:, stop_loss:, take_profit:, trailing_stop_pct: nil, trailing_stop_amount: nil)
      @instrument_id = instrument_id
      @entry_date = entry_date
      @entry_price = entry_price.to_f
      @quantity = quantity.to_i
      @direction = direction.to_sym
      @initial_stop_loss = stop_loss.to_f
      @stop_loss = stop_loss.to_f
      @take_profit = take_profit.to_f
      @trailing_stop_pct = trailing_stop_pct
      @trailing_stop_amount = trailing_stop_amount
      @exit_date = nil
      @exit_price = nil
      @exit_reason = nil
      @highest_price = entry_price.to_f # Track highest price for long positions
      @lowest_price = entry_price.to_f  # Track lowest price for short positions
    end

    def close(exit_date:, exit_price:, exit_reason:)
      @exit_date = exit_date
      @exit_price = exit_price.to_f
      @exit_reason = exit_reason
    end

    def closed?
      @exit_date.present?
    end

    def current_value(current_price = nil)
      price = current_price || @exit_price || @entry_price
      price * @quantity
    end

    def calculate_pnl(current_price = nil)
      price = current_price || @exit_price
      return 0 unless price

      case @direction
      when :long
        (price - @entry_price) * @quantity
      when :short
        (@entry_price - price) * @quantity
      else
        0
      end
    end

    def calculate_pnl_pct(current_price = nil)
      price = current_price || @exit_price
      return 0 unless price

      case @direction
      when :long
        ((price - @entry_price) / @entry_price * 100).round(4)
      when :short
        ((@entry_price - price) / @entry_price * 100).round(4)
      else
        0
      end
    end

    def check_exit(current_price, current_date)
      return nil if closed?

      # Update trailing stop if enabled
      update_trailing_stop(current_price) if trailing_stop_enabled?

      # Check stop loss (may have been updated by trailing stop)
      if @direction == :long && current_price <= @stop_loss
        reason = (@stop_loss != @initial_stop_loss) ? 'trailing_stop' : 'stop_loss'
        return { exit_price: @stop_loss, exit_reason: reason }
      elsif @direction == :short && current_price >= @stop_loss
        reason = (@stop_loss != @initial_stop_loss) ? 'trailing_stop' : 'stop_loss'
        return { exit_price: @stop_loss, exit_reason: reason }
      end

      # Check take profit
      if @direction == :long && current_price >= @take_profit
        return { exit_price: @take_profit, exit_reason: 'take_profit' }
      elsif @direction == :short && current_price <= @take_profit
        return { exit_price: @take_profit, exit_reason: 'take_profit' }
      end

      nil
    end

    def update_trailing_stop(current_price)
      return unless trailing_stop_enabled?

      case @direction
      when :long
        # Update highest price if current price is higher
        @highest_price = [@highest_price, current_price].max

        # Calculate new trailing stop
        new_stop = if @trailing_stop_pct
                     @highest_price * (1 - @trailing_stop_pct / 100.0)
                   elsif @trailing_stop_amount
                     @highest_price - @trailing_stop_amount
                   else
                     @stop_loss
                   end

        # Only move stop loss up (never down)
        @stop_loss = [new_stop, @stop_loss].max
      when :short
        # Update lowest price if current price is lower
        @lowest_price = [@lowest_price, current_price].min

        # Calculate new trailing stop
        new_stop = if @trailing_stop_pct
                     @lowest_price * (1 + @trailing_stop_pct / 100.0)
                   elsif @trailing_stop_amount
                     @lowest_price + @trailing_stop_amount
                   else
                     @stop_loss
                   end

        # Only move stop loss down (never up)
        @stop_loss = [new_stop, @stop_loss].min
      end
    end

    def trailing_stop_enabled?
      @trailing_stop_pct.present? || @trailing_stop_amount.present?
    end

    def holding_days(current_date = nil)
      end_date = current_date || @exit_date || Date.today
      (end_date.to_date - @entry_date.to_date).to_i
    end
  end
end

