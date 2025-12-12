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

    it 'calculates all metrics' do
      analyzer = described_class.new(
        positions: positions,
        initial_capital: initial_capital,
        final_capital: final_capital
      )

      results = analyzer.analyze

      expect(results).to have_key(:total_return)
      expect(results).to have_key(:annualized_return)
      expect(results).to have_key(:max_drawdown)
      expect(results).to have_key(:sharpe_ratio)
      expect(results).to have_key(:sortino_ratio)
      expect(results).to have_key(:win_rate)
      expect(results).to have_key(:profit_factor)
      expect(results).to have_key(:total_trades)
      expect(results).to have_key(:equity_curve)
      expect(results).to have_key(:monthly_returns)
    end

    context 'with zero initial capital' do
      it 'handles zero capital gracefully' do
        analyzer = described_class.new(
          positions: positions,
          initial_capital: 0.0,
          final_capital: 1000.0
        )

        results = analyzer.analyze

        expect(results[:total_return]).to eq(0)
        expect(results[:annualized_return]).to eq(0)
      end
    end

    context 'with no positions' do
      it 'handles empty positions' do
        analyzer = described_class.new(
          positions: [],
          initial_capital: initial_capital,
          final_capital: final_capital
        )

        results = analyzer.analyze

        expect(results[:total_trades]).to eq(0)
        expect(results[:win_rate]).to eq(0)
        expect(results[:profit_factor]).to eq(0)
      end
    end

    context 'with all losing trades' do
      let(:losing_positions) do
        [
          create_position(pnl: -500.0),
          create_position(pnl: -1000.0)
        ]
      end

      it 'calculates metrics correctly' do
        analyzer = described_class.new(
          positions: losing_positions,
          initial_capital: initial_capital,
          final_capital: 95_000.0
        )

        results = analyzer.analyze

        expect(results[:win_rate]).to eq(0)
        expect(results[:profit_factor]).to eq(0)
      end
    end

    context 'with all winning trades' do
      let(:winning_positions) do
        [
          create_position(pnl: 1000.0),
          create_position(pnl: 2000.0)
        ]
      end

      it 'calculates metrics correctly' do
        analyzer = described_class.new(
          positions: winning_positions,
          initial_capital: initial_capital,
          final_capital: 103_000.0
        )

        results = analyzer.analyze

        expect(results[:win_rate]).to eq(100.0)
        expect(results[:profit_factor]).to be > 0
      end
    end

    context 'with edge cases' do
      it 'handles zero standard deviation in Sharpe ratio' do
        # Create positions with identical returns
        identical_positions = [
          create_position(pnl: 100.0),
          create_position(pnl: 100.0),
          create_position(pnl: 100.0)
        ]

        analyzer = described_class.new(
          positions: identical_positions,
          initial_capital: initial_capital,
          final_capital: final_capital
        )

        results = analyzer.analyze

        expect(results[:sharpe_ratio]).to eq(0)
      end

      it 'handles zero downside deviation in Sortino ratio' do
        # All winning trades
        winning_positions = [
          create_position(pnl: 100.0),
          create_position(pnl: 200.0)
        ]

        analyzer = described_class.new(
          positions: winning_positions,
          initial_capital: initial_capital,
          final_capital: final_capital
        )

        results = analyzer.analyze

        expect(results[:sortino_ratio]).to eq(0)
      end
    end
  end

  describe 'private methods' do
    let(:analyzer) { described_class.new(positions: positions, initial_capital: initial_capital, final_capital: final_capital) }

    describe '#total_return' do
      it 'calculates return percentage' do
        return_pct = analyzer.send(:total_return)
        expect(return_pct).to eq(10.0) # (110_000 - 100_000) / 100_000 * 100
      end

      it 'returns 0 for zero initial capital' do
        analyzer_zero = described_class.new(positions: positions, initial_capital: 0.0, final_capital: 1000.0)
        expect(analyzer_zero.send(:total_return)).to eq(0)
      end
    end

    describe '#annualized_return' do
      it 'calculates annualized return' do
        allow(analyzer).to receive(:trading_days).and_return(252)
        annualized = analyzer.send(:annualized_return)
        expect(annualized).to be_a(Float)
      end

      it 'returns 0 for zero trading days' do
        allow(analyzer).to receive(:trading_days).and_return(0)
        expect(analyzer.send(:annualized_return)).to eq(0)
      end

      it 'returns 0 for zero initial capital' do
        analyzer_zero = described_class.new(positions: positions, initial_capital: 0.0, final_capital: 1000.0)
        expect(analyzer_zero.send(:annualized_return)).to eq(0)
      end
    end

    describe '#max_drawdown' do
      it 'calculates max drawdown from equity curve' do
        allow(analyzer).to receive(:equity_curve_data).and_return([
          { equity: 100_000 },
          { equity: 105_000 },
          { equity: 95_000 },  # Drawdown
          { equity: 110_000 }
        ])
        drawdown = analyzer.send(:max_drawdown)
        expect(drawdown).to be > 0
      end

      it 'returns 0 for empty equity curve' do
        allow(analyzer).to receive(:equity_curve_data).and_return([])
        expect(analyzer.send(:max_drawdown)).to eq(0)
      end
    end

    describe '#sharpe_ratio' do
      it 'calculates Sharpe ratio' do
        allow(analyzer).to receive(:period_returns).and_return([0.01, 0.02, -0.01, 0.03])
        sharpe = analyzer.send(:sharpe_ratio)
        expect(sharpe).to be_a(Float)
      end

      it 'returns 0 for empty returns' do
        allow(analyzer).to receive(:period_returns).and_return([])
        expect(analyzer.send(:sharpe_ratio)).to eq(0)
      end

      it 'returns 0 for zero standard deviation' do
        allow(analyzer).to receive(:period_returns).and_return([0.01, 0.01, 0.01])
        expect(analyzer.send(:sharpe_ratio)).to eq(0)
      end
    end

    describe '#sortino_ratio' do
      it 'calculates Sortino ratio' do
        allow(analyzer).to receive(:period_returns).and_return([0.01, 0.02, -0.01, 0.03])
        sortino = analyzer.send(:sortino_ratio)
        expect(sortino).to be_a(Float)
      end

      it 'returns 0 for empty returns' do
        allow(analyzer).to receive(:period_returns).and_return([])
        expect(analyzer.send(:sortino_ratio)).to eq(0)
      end

      it 'returns 0 for no downside returns' do
        allow(analyzer).to receive(:period_returns).and_return([0.01, 0.02, 0.03])
        expect(analyzer.send(:sortino_ratio)).to eq(0)
      end
    end

    describe '#avg_win_loss_ratio' do
      it 'calculates average win/loss ratio' do
        ratio = analyzer.send(:avg_win_loss_ratio)
        expect(ratio).to be >= 0
      end

      it 'returns 0 if no wins' do
        losing_only = [create_position(pnl: -100.0), create_position(pnl: -200.0)]
        analyzer_losing = described_class.new(positions: losing_only, initial_capital: initial_capital, final_capital: 99_700.0)
        expect(analyzer_losing.send(:avg_win_loss_ratio)).to eq(0)
      end

      it 'returns 0 if no losses' do
        winning_only = [create_position(pnl: 100.0), create_position(pnl: 200.0)]
        analyzer_winning = described_class.new(positions: winning_only, initial_capital: initial_capital, final_capital: 100_300.0)
        expect(analyzer_winning.send(:avg_win_loss_ratio)).to eq(0)
      end
    end

    describe '#profit_factor' do
      it 'calculates profit factor' do
        factor = analyzer.send(:profit_factor)
        expect(factor).to be >= 0
      end

      it 'returns 0 for zero gross loss' do
        winning_only = [create_position(pnl: 100.0), create_position(pnl: 200.0)]
        analyzer_winning = described_class.new(positions: winning_only, initial_capital: initial_capital, final_capital: 100_300.0)
        expect(analyzer_winning.send(:profit_factor)).to eq(0)
      end
    end

    describe '#best_trade and #worst_trade' do
      it 'returns nil for empty positions' do
        analyzer_empty = described_class.new(positions: [], initial_capital: initial_capital, final_capital: final_capital)
        expect(analyzer_empty.send(:best_trade)).to be_nil
        expect(analyzer_empty.send(:worst_trade)).to be_nil
      end

      it 'returns trade details' do
        best = analyzer.send(:best_trade)
        worst = analyzer.send(:worst_trade)

        expect(best).to have_key(:pnl)
        expect(best).to have_key(:pnl_pct)
        expect(best).to have_key(:holding_days)
        expect(worst).to have_key(:pnl)
        expect(worst).to have_key(:pnl_pct)
        expect(worst).to have_key(:holding_days)
      end
    end

    describe '#consecutive_wins and #consecutive_losses' do
      it 'calculates max consecutive wins' do
        consecutive_positions = [
          create_position(pnl: 100.0),
          create_position(pnl: 200.0),
          create_position(pnl: 150.0),
          create_position(pnl: -50.0),
          create_position(pnl: 100.0)
        ]
        analyzer_consecutive = described_class.new(positions: consecutive_positions, initial_capital: initial_capital, final_capital: 100_500.0)
        expect(analyzer_consecutive.send(:consecutive_wins)).to eq(3)
      end

      it 'calculates max consecutive losses' do
        consecutive_positions = [
          create_position(pnl: -100.0),
          create_position(pnl: -200.0),
          create_position(pnl: -150.0),
          create_position(pnl: 50.0),
          create_position(pnl: -100.0)
        ]
        analyzer_consecutive = described_class.new(positions: consecutive_positions, initial_capital: initial_capital, final_capital: 99_450.0)
        expect(analyzer_consecutive.send(:consecutive_losses)).to eq(3)
      end
    end

    describe '#trading_days' do
      it 'calculates trading days from positions' do
        days = analyzer.send(:trading_days)
        expect(days).to be >= 0
      end

      it 'returns 0 for empty positions' do
        analyzer_empty = described_class.new(positions: [], initial_capital: initial_capital, final_capital: final_capital)
        expect(analyzer_empty.send(:trading_days)).to eq(0)
      end

      it 'handles positions without exit_date' do
        position_no_exit = create_position(pnl: 100.0)
        position_no_exit.instance_variable_set(:@exit_date, nil)
        analyzer_no_exit = described_class.new(positions: [position_no_exit], initial_capital: initial_capital, final_capital: 100_100.0)
        days = analyzer_no_exit.send(:trading_days)
        expect(days).to be >= 0
      end
    end

    describe '#avg_holding_period' do
      it 'calculates average holding period' do
        period = analyzer.send(:avg_holding_period)
        expect(period).to be >= 0
      end

      it 'returns 0 for empty positions' do
        analyzer_empty = described_class.new(positions: [], initial_capital: initial_capital, final_capital: final_capital)
        expect(analyzer_empty.send(:avg_holding_period)).to eq(0)
      end
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

