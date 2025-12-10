# frozen_string_literal: true

module Backtesting
  # Virtual position tracker for backtesting
  class Position
    attr_reader :instrument_id, :entry_date, :entry_price, :quantity, :direction, :stop_loss, :take_profit
    attr_accessor :exit_date, :exit_price, :exit_reason

    def initialize(instrument_id:, entry_date:, entry_price:, quantity:, direction:, stop_loss:, take_profit:)
      @instrument_id = instrument_id
      @entry_date = entry_date
      @entry_price = entry_price.to_f
      @quantity = quantity.to_i
      @direction = direction.to_sym
      @stop_loss = stop_loss.to_f
      @take_profit = take_profit.to_f
      @exit_date = nil
      @exit_price = nil
      @exit_reason = nil
    end

    def close(exit_date:, exit_price:, exit_reason:)
      @exit_date = exit_date
      @exit_price = exit_price.to_f
      @exit_reason = exit_reason
    end

    def closed?
      @exit_date.present?
    end

    def current_value(current_price)
      current_price * @quantity
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

      # Check stop loss
      if @direction == :long && current_price <= @stop_loss
        return { exit_price: @stop_loss, exit_reason: 'stop_loss' }
      elsif @direction == :short && current_price >= @stop_loss
        return { exit_price: @stop_loss, exit_reason: 'stop_loss' }
      end

      # Check take profit
      if @direction == :long && current_price >= @take_profit
        return { exit_price: @take_profit, exit_reason: 'take_profit' }
      elsif @direction == :short && current_price <= @take_profit
        return { exit_price: @take_profit, exit_reason: 'take_profit' }
      end

      nil
    end

    def holding_days(current_date = nil)
      end_date = current_date || @exit_date || Date.today
      (end_date.to_date - @entry_date.to_date).to_i
    end
  end
end

