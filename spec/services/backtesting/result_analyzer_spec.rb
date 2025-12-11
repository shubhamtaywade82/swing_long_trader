# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtesting::ResultAnalyzer, type: :service do
  let(:initial_capital) { 100_000.0 }
  let(:final_capital) { 110_000.0 }
  let(:positions) { create_test_positions }

  describe '#analyze' do
    it 'calculates total return' do
      analyzer = described_class.new(
        positions: positions,
        initial_capital: initial_capital,
        final_capital: final_capital
      )

      total_return = analyzer.analyze[:total_return]
      expected = ((final_capital - initial_capital) / initial_capital * 100).round(2)

      expect(total_return).to eq(expected)
    end

    it 'calculates win rate' do
      analyzer = described_class.new(
        positions: positions,
        initial_capital: initial_capital,
        final_capital: final_capital
      )

      win_rate = analyzer.analyze[:win_rate]
      # 2 winning, 1 losing = 66.67%
      expect(win_rate).to be_within(0.1).of(66.67)
    end

    it 'calculates profit factor' do
      analyzer = described_class.new(
        positions: positions,
        initial_capital: initial_capital,
        final_capital: final_capital
      )

      profit_factor = analyzer.analyze[:profit_factor]
      # Should be > 1 if profitable
      expect(profit_factor).to be > 0
    end

    it 'finds best and worst trade' do
      analyzer = described_class.new(
        positions: positions,
        initial_capital: initial_capital,
        final_capital: final_capital
      )

      results = analyzer.analyze
      expect(results[:best_trade]).not_to be_nil
      expect(results[:worst_trade]).not_to be_nil
      expect(results[:best_trade][:pnl]).to be > results[:worst_trade][:pnl]
    end

    it 'calculates consecutive wins and losses' do
      analyzer = described_class.new(
        positions: positions,
        initial_capital: initial_capital,
        final_capital: final_capital
      )

      results = analyzer.analyze
      expect(results[:consecutive_wins]).to be >= 0
      expect(results[:consecutive_losses]).to be >= 0
    end
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

