# frozen_string_literal: true

module TradingSignals
  # Simulates execution of trading signals to calculate what-if P&L
  # Useful for analyzing signals that weren't executed due to insufficient balance or other reasons
  class Simulator < ApplicationService
    def self.simulate(signal, end_date: nil)
      new(signal: signal, end_date: end_date).simulate
    end

    def self.simulate_all_not_executed(end_date: nil)
      signals = TradingSignal.not_executed.where(simulated: false)
      results = []

      signals.find_each do |signal|
        result = simulate(signal, end_date: end_date)
        results << result if result[:success]
      end

      {
        success: true,
        simulated_count: results.size,
        results: results,
      }
    end

    def initialize(signal:, end_date: nil)
      @signal = signal.is_a?(TradingSignal) ? signal : TradingSignal.find(signal)
      @instrument = @signal.instrument
      @end_date = end_date || Time.current.to_date
      @start_date = @signal.signal_generated_at.to_date
    end

    def simulate
      return { success: false, error: "Signal already executed" } if @signal.executed?
      return { success: false, error: "Instrument not found" } unless @instrument

      # Load candles for the period
      daily_series = load_candles_for_period
      return { success: false, error: "Insufficient candle data" } unless daily_series&.candles&.any?

      # Simulate entry and exit
      simulation_result = simulate_trade(daily_series)

      # Update signal record
      update_signal_with_simulation(simulation_result)

      {
        success: true,
        signal: @signal,
        simulation: simulation_result,
      }
    rescue StandardError => e
      Rails.logger.error("[TradingSignals::Simulator] Simulation failed: #{e.message}")
      {
        success: false,
        error: e.message,
      }
    end

    private

    def load_candles_for_period
      # Load candles from signal generation date to end date
      # Need enough candles before signal date for indicators
      days_before = 100
      start_load_date = @start_date - days_before.days

      @instrument.load_daily_candles(
        from_date: start_load_date,
        to_date: @end_date,
        limit: 200,
      )
    end

    def simulate_trade(series)
      entry_date = @start_date
      entry_price = @signal.entry_price
      stop_loss = @signal.stop_loss
      take_profit = @signal.take_profit
      quantity = @signal.quantity
      direction = @signal.direction.to_sym

      # Find candles after entry date
      entry_candle_index = find_candle_index_for_date(series, entry_date)
      return { success: false, error: "Entry date not found in candles" } unless entry_candle_index

      # Simulate exit conditions
      exit_result = check_exit_conditions(
        series: series,
        start_index: entry_candle_index,
        entry_price: entry_price,
        stop_loss: stop_loss,
        take_profit: take_profit,
        direction: direction,
      )

      # Calculate P&L
      exit_price = exit_result[:exit_price]
      exit_date = exit_result[:exit_date]
      exit_reason = exit_result[:exit_reason]
      holding_days = (exit_date.to_date - entry_date).to_i

      pnl = calculate_pnl(entry_price, exit_price, quantity, direction)
      pnl_pct = calculate_pnl_pct(entry_price, exit_price, direction)

      {
        success: true,
        entry_date: entry_date,
        entry_price: entry_price,
        exit_date: exit_date,
        exit_price: exit_price,
        exit_reason: exit_reason,
        holding_days: holding_days,
        pnl: pnl,
        pnl_pct: pnl_pct,
        stop_loss_hit: exit_reason == "sl_hit",
        take_profit_hit: exit_reason == "tp_hit",
        metadata: {
          stop_loss: stop_loss,
          take_profit: take_profit,
          direction: direction,
          quantity: quantity,
          simulated_at: Time.current,
        },
      }
    end

    def find_candle_index_for_date(series, target_date)
      series.candles.each_with_index do |candle, index|
        return index if candle.timestamp.to_date >= target_date
      end
      nil
    end

    def check_exit_conditions(series:, start_index:, entry_price:, stop_loss:, take_profit:, direction:)
      candles = series.candles[start_index..]
      return default_exit(series.candles.last) unless candles&.any?

      candles.each do |candle|
        current_date = candle.timestamp.to_date
        return default_exit(candle) if current_date > @end_date

        # Check stop loss
        if stop_loss
          sl_hit = if direction == :long
                     candle.low <= stop_loss
                   else
                     candle.high >= stop_loss
                   end

          if sl_hit
            return {
              exit_date: current_date,
              exit_price: stop_loss,
              exit_reason: "sl_hit",
            }
          end
        end

        # Check take profit
        if take_profit
          tp_hit = if direction == :long
                     candle.high >= take_profit
                   else
                     candle.low <= take_profit
                   end

          if tp_hit
            return {
              exit_date: current_date,
              exit_price: take_profit,
              exit_reason: "tp_hit",
            }
          end
        end
      end

      # If no exit condition hit, exit at end date or last candle
      last_candle = candles.last || series.candles.last
      exit_price = if direction == :long
                     last_candle.close
                   else
                     last_candle.close
                   end

      {
        exit_date: [@end_date, last_candle.timestamp.to_date].min,
        exit_price: exit_price,
        exit_reason: "time_based",
      }
    end

    def default_exit(last_candle)
      direction = @signal.direction.to_sym
      exit_price = last_candle.close

      {
        exit_date: last_candle.timestamp.to_date,
        exit_price: exit_price,
        exit_reason: "time_based",
      }
    end

    def calculate_pnl(entry_price, exit_price, quantity, direction)
      if direction == :long
        (exit_price - entry_price) * quantity
      else
        (entry_price - exit_price) * quantity
      end
    end

    def calculate_pnl_pct(entry_price, exit_price, direction)
      return 0 if entry_price.zero?

      if direction == :long
        ((exit_price - entry_price) / entry_price * 100).round(2)
      else
        ((entry_price - exit_price) / entry_price * 100).round(2)
      end
    end

    def update_signal_with_simulation(result)
      @signal.update!(
        simulated: true,
        simulated_at: Time.current,
        simulated_exit_price: result[:exit_price],
        simulated_exit_date: result[:exit_date],
        simulated_exit_reason: result[:exit_reason],
        simulated_pnl: result[:pnl],
        simulated_pnl_pct: result[:pnl_pct],
        simulated_holding_days: result[:holding_days],
        simulation_metadata: result[:metadata].to_json,
      )
    end
  end
end
