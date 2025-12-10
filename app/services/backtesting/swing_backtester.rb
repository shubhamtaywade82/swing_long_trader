# frozen_string_literal: true

module Backtesting
  # Swing trading backtester
  class SwingBacktester < ApplicationService
    def self.call(instruments:, from_date:, to_date:, initial_capital: 100_000, risk_per_trade: 2.0)
      new(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date,
        initial_capital: initial_capital,
        risk_per_trade: risk_per_trade
      ).call
    end

    def initialize(instruments:, from_date:, to_date:, initial_capital: 100_000, risk_per_trade: 2.0)
      @instruments = instruments
      @from_date = from_date
      @to_date = to_date
      @initial_capital = initial_capital
      @risk_per_trade = risk_per_trade
      @portfolio = Portfolio.new(initial_capital: @initial_capital)
      @positions = []
    end

    def call
      # Load historical data
      daily_data = DataLoader.load_for_instruments(
        instruments: @instruments,
        timeframe: '1D',
        from_date: @from_date,
        to_date: @to_date
      )

      validated_data = DataLoader.new.validate_data(daily_data, min_candles: 50)
      return { success: false, error: 'Insufficient data' } if validated_data.empty?

      # Walk forward through dates (avoid look-ahead bias)
      current_date = @from_date
      while current_date <= @to_date
        process_date(current_date, validated_data)
        current_date += 1.day
      end

      # Close any remaining open positions
      close_all_positions(@to_date, validated_data)

      # Analyze results
      analyzer = ResultAnalyzer.new(
        positions: @positions,
        initial_capital: @initial_capital,
        final_capital: @portfolio.current_equity
      )

      results = analyzer.analyze

      {
        success: true,
        results: results,
        positions: @positions,
        portfolio: @portfolio
      }
    end

    private

    def process_date(date, data)
      # Check for entry signals
      data.each do |instrument_id, series|
        next if @portfolio.positions[instrument_id] # Already have position

        # Get candles up to current date (no look-ahead)
        historical_candles = series.candles.select { |c| c.timestamp.to_date <= date }
        next if historical_candles.size < 50

        # Create temporary series for signal generation
        temp_series = CandleSeries.new(symbol: series.symbol, interval: series.interval)
        historical_candles.each { |c| temp_series.add_candle(c) }

        # Check for entry signal
        instrument = Instrument.find_by(id: instrument_id)
        next unless instrument

        signal = check_entry_signal(instrument, temp_series, date)
        next unless signal

        # Open position
        open_position(instrument, signal, date)
      end

      # Check for exit signals on open positions
      check_exits(date, data)
    end

    def check_entry_signal(instrument, series, date)
      # Use strategy engine to generate signal
      result = Strategies::Swing::Engine.call(
        instrument: instrument,
        daily_series: series
      )

      return nil unless result[:success]

      signal = result[:signal]
      return nil unless signal

      # Verify signal is valid for this date
      latest_candle = series.candles.last
      return nil unless latest_candle&.timestamp&.to_date == date

      signal
    end

    def open_position(instrument, signal, date)
      entry_price = signal[:entry_price]
      quantity = signal[:qty]
      direction = signal[:direction]
      stop_loss = signal[:sl]
      take_profit = signal[:tp]

      success = @portfolio.open_position(
        instrument_id: instrument.id,
        entry_date: date,
        entry_price: entry_price,
        quantity: quantity,
        direction: direction,
        stop_loss: stop_loss,
        take_profit: take_profit
      )

      return unless success

      position = @portfolio.positions[instrument.id]
      @positions << position if position
    end

    def check_exits(date, data)
      @portfolio.positions.each do |instrument_id, position|
        next if position.closed?

        series = data[instrument_id]
        next unless series

        # Get current price for this date
        current_candle = series.candles.find { |c| c.timestamp.to_date == date }
        next unless current_candle

        current_price = current_candle.close

        # Check exit conditions
        exit_check = position.check_exit(current_price, date)
        next unless exit_check

        # Close position
        @portfolio.close_position(
          instrument_id: instrument_id,
          exit_date: date,
          exit_price: exit_check[:exit_price],
          exit_reason: exit_check[:exit_reason]
        )
      end
    end

    def close_all_positions(end_date, data)
      @portfolio.positions.each do |instrument_id, position|
        next if position.closed?

        series = data[instrument_id]
        current_price = series&.candles&.last&.close || position.entry_price

        @portfolio.close_position(
          instrument_id: instrument_id,
          exit_date: end_date,
          exit_price: current_price,
          exit_reason: 'end_of_backtest'
        )
      end
    end
  end
end

