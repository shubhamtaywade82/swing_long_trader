# frozen_string_literal: true

module Backtesting
  # Long-term trading backtester with rebalancing
  class LongTermBacktester < ApplicationService
    def self.call(instruments:, from_date:, to_date:, initial_capital: 100_000, risk_per_trade: 2.0,
                  rebalance_frequency: :weekly, max_positions: 10, min_holding_days: 30, commission_rate: 0.0,
                  slippage_pct: 0.0)
      new(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date,
        initial_capital: initial_capital,
        risk_per_trade: risk_per_trade,
        rebalance_frequency: rebalance_frequency,
        max_positions: max_positions,
        min_holding_days: min_holding_days,
        commission_rate: commission_rate,
        slippage_pct: slippage_pct,
      ).call
    end

    def initialize(instruments:, from_date:, to_date:, initial_capital: 100_000, risk_per_trade: 2.0,
                   rebalance_frequency: :weekly, max_positions: 10, min_holding_days: 30, commission_rate: 0.0,
                   slippage_pct: 0.0)
      super()
      @instruments = instruments
      @from_date = from_date
      @to_date = to_date
      @initial_capital = initial_capital
      @risk_per_trade = risk_per_trade
      @rebalance_frequency = rebalance_frequency.to_sym
      @max_positions = max_positions
      @min_holding_days = min_holding_days
      @config = Config.new(
        initial_capital: @initial_capital,
        risk_per_trade: @risk_per_trade,
        commission_rate: commission_rate,
        slippage_pct: slippage_pct,
      )
      @portfolio = Portfolio.new(initial_capital: @initial_capital, config: @config)
      @positions = []
      @portfolio_composition = [] # Track portfolio composition over time
      @last_rebalance_date = nil
      @long_term_config = AlgoConfig.fetch(:long_term_trading) || {}
      @strategy_config = @long_term_config[:strategy] || {}
      @exit_config = @strategy_config[:exit_conditions] || {}
    end

    def call
      # Load historical data (daily and weekly)
      daily_data = DataLoader.load_for_instruments(
        instruments: @instruments,
        timeframe: :daily,
        from_date: @from_date,
        to_date: @to_date,
      )

      weekly_data = DataLoader.load_for_instruments(
        instruments: @instruments,
        timeframe: :weekly,
        from_date: @from_date,
        to_date: @to_date,
      )

      validated_daily = DataLoader.new.validate_data(daily_data, min_candles: 50)
      validated_weekly = DataLoader.new.validate_data(weekly_data, min_candles: 10)
      return { success: false, error: "Insufficient data" } if validated_daily.empty? || validated_weekly.empty?

      # Walk forward through dates (avoid look-ahead bias)
      current_date = @from_date
      while current_date <= @to_date
        process_date(current_date, validated_daily, validated_weekly)
        current_date += 1.day
      end

      # Close any remaining open positions
      close_all_positions(@to_date, validated_daily)

      # Analyze results
      analyzer = ResultAnalyzer.new(
        positions: @positions,
        initial_capital: @initial_capital,
        final_capital: @portfolio.current_equity,
      )

      results = analyzer.analyze

      # Add long-term specific metrics
      results[:total_commission] = @portfolio.total_commission.round(2)
      results[:total_slippage] = @portfolio.total_slippage.round(2)
      results[:total_trading_costs] = (@portfolio.total_commission + @portfolio.total_slippage).round(2)
      results[:portfolio_composition_history] = @portfolio_composition
      results[:rebalance_count] = @portfolio_composition.size
      results[:avg_positions_per_rebalance] = calculate_avg_positions_per_rebalance

      {
        success: true,
        results: results,
        positions: @positions,
        portfolio: @portfolio,
      }
    end

    private

    def process_date(date, daily_data, weekly_data)
      # Check if it's time to rebalance
      if should_rebalance?(date)
        rebalance_portfolio(date, daily_data, weekly_data)
        @last_rebalance_date = date
      end

      # Check for exit signals on open positions
      check_exits(date, daily_data)
    end

    def should_rebalance?(date)
      return true if @last_rebalance_date.nil?

      case @rebalance_frequency
      when :weekly
        # Rebalance on Mondays
        date.monday? && date > @last_rebalance_date
      when :monthly
        # Rebalance on first trading day of month
        date.day == 1 && date > @last_rebalance_date
      else
        false
      end
    end

    def rebalance_portfolio(date, daily_data, weekly_data)
      # Close positions that don't meet minimum holding period or exit conditions
      close_positions_for_rebalance(date, daily_data)

      # Check if we have room for new positions
      available_slots = @max_positions - @portfolio.positions.size
      return if available_slots <= 0

      # Find new candidates
      candidates = find_candidates(date, daily_data, weekly_data, available_slots)

      # Open new positions
      candidates.each do |candidate|
        next if @portfolio.positions[candidate[:instrument_id]] # Already have position

        signal = check_entry_signal(candidate, date, daily_data, weekly_data)
        next unless signal

        open_position(candidate[:instrument], signal, date)
        available_slots -= 1
        break if available_slots <= 0
      end

      # Track portfolio composition
      track_portfolio_composition(date)
    end

    def close_positions_for_rebalance(date, daily_data)
      @portfolio.positions.each do |instrument_id, position|
        next if position.closed?

        # Check minimum holding period
        holding_days = position.holding_days(date)
        if holding_days < @min_holding_days
          next # Don't close if hasn't met minimum holding period
        end

        # Check exit conditions
        series = daily_data[instrument_id]
        next unless series

        current_candle = series.candles.find { |c| c.timestamp.to_date == date }
        next unless current_candle

        current_price = current_candle.close

        # Check exit conditions
        exit_check = check_long_term_exit(position, current_price, date, holding_days)
        next unless exit_check

        # Close position
        @portfolio.close_position(
          instrument_id: instrument_id,
          exit_date: date,
          exit_price: exit_check[:exit_price],
          exit_reason: exit_check[:exit_reason],
        )
      end
    end

    def check_long_term_exit(position, current_price, date, _holding_days)
      # Check stop loss
      if position.direction == :long && current_price <= position.stop_loss
        return { exit_price: position.stop_loss, exit_reason: "stop_loss" }
      end

      # Check take profit
      if position.direction == :long && current_price >= position.take_profit
        return { exit_price: position.take_profit, exit_reason: "take_profit" }
      end

      # Check time-based exit (after minimum holding period)
      # This is handled in close_positions_for_rebalance

      # Check trailing stop if enabled
      exit_check = position.check_exit(current_price, date)
      return exit_check if exit_check

      nil
    end

    def find_candidates(date, daily_data, weekly_data, limit)
      candidates = []

      daily_data.each do |instrument_id, daily_series|
        next if @portfolio.positions[instrument_id] # Already have position

        weekly_series = weekly_data[instrument_id]
        next unless weekly_series

        # Get candles up to current date (no look-ahead)
        historical_daily = daily_series.candles.select { |c| c.timestamp.to_date <= date }
        historical_weekly = weekly_series.candles.select { |c| c.timestamp.to_date <= date }
        next if historical_daily.size < 50 || historical_weekly.size < 10

        instrument = Instrument.find_by(id: instrument_id)
        next unless instrument

        # Create candidate
        candidates << {
          instrument_id: instrument_id,
          instrument: instrument,
          daily_series: historical_daily,
          weekly_series: historical_weekly,
        }
      end

      # Limit candidates
      candidates.first(limit)
    end

    def check_entry_signal(candidate, date, _daily_data, _weekly_data)
      instrument = candidate[:instrument]

      # Create temporary series for signal generation
      temp_daily = CandleSeries.new(symbol: instrument.symbol_name, interval: :daily)
      candidate[:daily_series].each { |c| temp_daily.add_candle(c) }

      temp_weekly = CandleSeries.new(symbol: instrument.symbol_name, interval: :weekly)
      candidate[:weekly_series].each { |c| temp_weekly.add_candle(c) }

      # Use long-term strategy evaluator
      # Create a candidate hash similar to what screener would produce
      screener_candidate = {
        instrument_id: instrument.id,
        symbol: instrument.symbol_name,
        score: 70.0, # Default score for backtesting
      }

      result = Strategies::LongTerm::Evaluator.call(screener_candidate)

      return nil unless result[:success]

      signal = result[:signal]
      return nil unless signal

      # Verify signal is valid for this date
      latest_daily = temp_daily.candles.last
      return nil unless latest_daily&.timestamp&.to_date == date

      signal
    end

    def open_position(instrument, signal, date)
      entry_price = signal[:entry_price]
      quantity = signal[:qty]
      direction = signal[:direction]
      stop_loss = signal[:sl]
      take_profit = signal[:tp]

      # Get trailing stop from config
      trailing_stop_pct = @exit_config[:trailing_stop_pct]

      success = @portfolio.open_position(
        instrument_id: instrument.id,
        entry_date: date,
        entry_price: entry_price,
        quantity: quantity,
        direction: direction,
        stop_loss: stop_loss,
        take_profit: take_profit,
        trailing_stop_pct: trailing_stop_pct,
      )

      return unless success

      position = @portfolio.positions[instrument.id]
      @positions << position if position
    end

    def check_exits(date, daily_data)
      @portfolio.positions.each do |instrument_id, position|
        next if position.closed?

        # Check minimum holding period
        holding_days = position.holding_days(date)
        next if holding_days < @min_holding_days

        series = daily_data[instrument_id]
        next unless series

        # Get current price for this date
        current_candle = series.candles.find { |c| c.timestamp.to_date == date }
        next unless current_candle

        current_price = current_candle.close

        # Check exit conditions
        exit_check = check_long_term_exit(position, current_price, date, holding_days)
        next unless exit_check

        # Close position
        @portfolio.close_position(
          instrument_id: instrument_id,
          exit_date: date,
          exit_price: exit_check[:exit_price],
          exit_reason: exit_check[:exit_reason],
        )
      end
    end

    def close_all_positions(end_date, daily_data)
      @portfolio.positions.each do |instrument_id, position|
        next if position.closed?

        series = daily_data[instrument_id]
        current_price = series&.candles&.last&.close || position.entry_price

        @portfolio.close_position(
          instrument_id: instrument_id,
          exit_date: end_date,
          exit_price: current_price,
          exit_reason: "end_of_backtest",
        )
      end
    end

    def track_portfolio_composition(date)
      composition = {
        date: date,
        positions: @portfolio.positions.size,
        instruments: @portfolio.positions.keys.map do |id|
          instrument = Instrument.find_by(id: id)
          instrument ? instrument.symbol_name : "ID:#{id}"
        end,
        equity: @portfolio.current_equity,
      }

      @portfolio_composition << composition
    end

    def calculate_avg_positions_per_rebalance
      return 0 if @portfolio_composition.empty?

      total_positions = @portfolio_composition.sum { |c| c[:positions] }
      (total_positions.to_f / @portfolio_composition.size).round(2)
    end
  end
end
