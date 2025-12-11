# frozen_string_literal: true

require 'test_helper'

module Backtesting
  class ResultAnalyzerTest < ActiveSupport::TestCase
    setup do
      @initial_capital = 100_000.0
      @final_capital = 110_000.0
      @positions = create_test_positions
    end

    test 'should calculate total return' do
      analyzer = ResultAnalyzer.new(
        positions: @positions,
        initial_capital: @initial_capital,
        final_capital: @final_capital
      )

      total_return = analyzer.analyze[:total_return]
      expected = ((@final_capital - @initial_capital) / @initial_capital * 100).round(2)

      assert_equal expected, total_return
    end

    test 'should calculate win rate' do
      analyzer = ResultAnalyzer.new(
        positions: @positions,
        initial_capital: @initial_capital,
        final_capital: @final_capital
      )

      win_rate = analyzer.analyze[:win_rate]
      # 2 winning, 1 losing = 66.67%
      assert_in_delta 66.67, win_rate, 0.1
    end

    test 'should calculate profit factor' do
      analyzer = ResultAnalyzer.new(
        positions: @positions,
        initial_capital: @initial_capital,
        final_capital: @final_capital
      )

      profit_factor = analyzer.analyze[:profit_factor]
      # Should be > 1 if profitable
      assert profit_factor > 0
    end

    test 'should find best and worst trade' do
      analyzer = ResultAnalyzer.new(
        positions: @positions,
        initial_capital: @initial_capital,
        final_capital: @final_capital
      )

      results = analyzer.analyze
      assert_not_nil results[:best_trade]
      assert_not_nil results[:worst_trade]
      assert results[:best_trade][:pnl] > results[:worst_trade][:pnl]
    end

    test 'should calculate consecutive wins and losses' do
      analyzer = ResultAnalyzer.new(
        positions: @positions,
        initial_capital: @initial_capital,
        final_capital: @final_capital
      )

      results = analyzer.analyze
      assert results[:consecutive_wins] >= 0
      assert results[:consecutive_losses] >= 0
    end

    private

    def create_test_positions
      [
        create_position(pnl: 1000.0),   # Win
        create_position(pnl: 2000.0),   # Win
        create_position(pnl: -500.0)    # Loss
      ]
    end

    def create_position(pnl:)
      instrument = create(:instrument)
      entry_price = 100.0
      exit_price = entry_price + (pnl / 10.0) # Simple calculation
      quantity = 10

      position = Backtesting::Position.new(
        instrument_id: instrument.id,
        entry_date: 5.days.ago.to_date,
        entry_price: entry_price,
        quantity: quantity,
        direction: :long,
        stop_loss: 95.0,
        take_profit: 110.0
      )

      position.close(
        exit_date: 1.day.ago.to_date,
        exit_price: exit_price,
        exit_reason: pnl > 0 ? 'take_profit' : 'stop_loss'
      )

      position
    end
  end
end

