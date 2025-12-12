# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtesting::MonteCarlo, type: :service do
  let(:positions) do
    [
      double(calculate_pnl: 100.0),
      double(calculate_pnl: -50.0),
      double(calculate_pnl: 200.0)
    ]
  end
  let(:initial_capital) { 100_000.0 }

  describe '.call' do
    it 'delegates to instance method' do
      allow_any_instance_of(described_class).to receive(:call).and_return({ success: true })

      described_class.call(
        positions: positions,
        initial_capital: initial_capital
      )

      expect_any_instance_of(described_class).to have_received(:call)
    end
  end

  describe '#call' do
    context 'when positions are provided' do
      it 'runs Monte Carlo simulations' do
        result = described_class.new(
          positions: positions,
          initial_capital: initial_capital,
          simulations: 10
        ).call

        expect(result[:success]).to be true
        expect(result[:simulations]).to eq(10)
        expect(result[:results]).to be_present
      end

      it 'calculates probability distributions' do
        result = described_class.new(
          positions: positions,
          initial_capital: initial_capital,
          simulations: 10
        ).call

        expect(result[:probability_distributions]).to be_present
      end

      it 'calculates confidence intervals' do
        result = described_class.new(
          positions: positions,
          initial_capital: initial_capital,
          simulations: 10
        ).call

        expect(result[:confidence_intervals]).to be_present
      end

      it 'calculates worst case scenarios' do
        result = described_class.new(
          positions: positions,
          initial_capital: initial_capital,
          simulations: 10
        ).call

        expect(result[:worst_case_scenarios]).to be_present
      end
    end

    context 'when no positions provided' do
      it 'returns error' do
        result = described_class.new(
          positions: [],
          initial_capital: initial_capital
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('No positions provided')
      end
    end

    context 'with different confidence levels' do
      it 'calculates confidence intervals for custom levels' do
        result = described_class.new(
          positions: positions,
          initial_capital: initial_capital,
          simulations: 10,
          confidence_levels: [0.80, 0.95]
        ).call

        expect(result[:confidence_intervals]).to be_present
        expect(result[:confidence_intervals].keys).to include(0.80, 0.95)
      end
    end

    context 'with edge cases' do
      it 'handles positions with zero PnL' do
        zero_pnl_positions = [
          double(calculate_pnl: 0.0),
          double(calculate_pnl: 0.0)
        ]

        result = described_class.new(
          positions: zero_pnl_positions,
          initial_capital: initial_capital,
          simulations: 10
        ).call

        expect(result[:success]).to be true
      end

      it 'handles all winning positions' do
        winning_positions = [
          double(calculate_pnl: 100.0),
          double(calculate_pnl: 200.0)
        ]

        result = described_class.new(
          positions: winning_positions,
          initial_capital: initial_capital,
          simulations: 10
        ).call

        expect(result[:success]).to be true
        expect(result[:results][:win_rate]).to eq(100.0)
      end

      it 'handles all losing positions' do
        losing_positions = [
          double(calculate_pnl: -50.0),
          double(calculate_pnl: -100.0)
        ]

        result = described_class.new(
          positions: losing_positions,
          initial_capital: initial_capital,
          simulations: 10
        ).call

        expect(result[:success]).to be true
        expect(result[:results][:win_rate]).to eq(0.0)
      end
    end

    describe 'private methods' do
      let(:monte_carlo) do
        described_class.new(
          positions: positions,
          initial_capital: initial_capital,
          simulations: 10
        )
      end

      describe '#run_simulation' do
        it 'simulates portfolio with randomized positions' do
          result = monte_carlo.send(:run_simulation)

          expect(result).to have_key(:final_capital)
          expect(result).to have_key(:total_return)
          expect(result).to have_key(:max_drawdown)
          expect(result).to have_key(:total_trades)
          expect(result).to have_key(:win_rate)
        end

        it 'handles zero initial capital' do
          monte_carlo = described_class.new(
            positions: positions,
            initial_capital: 0,
            simulations: 1
          )

          result = monte_carlo.send(:run_simulation)

          expect(result[:final_capital]).to be >= 0
        end

        it 'handles positions with zero PnL' do
          zero_pnl_positions = [
            double(calculate_pnl: 0.0),
            double(calculate_pnl: 0.0)
          ]

          monte_carlo = described_class.new(
            positions: zero_pnl_positions,
            initial_capital: initial_capital,
            simulations: 1
          )

          result = monte_carlo.send(:run_simulation)

          expect(result[:final_capital]).to eq(initial_capital)
          expect(result[:total_return]).to eq(0)
        end
      end

      describe '#analyze_results' do
        before do
          monte_carlo.instance_variable_set(:@simulation_results, [
            { final_capital: 110_000, total_return: 10.0, max_drawdown: 5.0, win_rate: 60.0 },
            { final_capital: 105_000, total_return: 5.0, max_drawdown: 3.0, win_rate: 55.0 }
          ])
        end

        it 'calculates mean and standard deviation' do
          analysis = monte_carlo.send(:analyze_results)

          expect(analysis).to have_key(:mean_final_capital)
          expect(analysis).to have_key(:mean_total_return)
          expect(analysis).to have_key(:std_dev_final_capital)
          expect(analysis).to have_key(:std_dev_total_return)
        end

        it 'calculates min and max values' do
          analysis = monte_carlo.send(:analyze_results)

          expect(analysis).to have_key(:min_final_capital)
          expect(analysis).to have_key(:max_final_capital)
          expect(analysis).to have_key(:min_total_return)
          expect(analysis).to have_key(:max_total_return)
        end

        it 'handles empty results' do
          monte_carlo.instance_variable_set(:@simulation_results, [])

          analysis = monte_carlo.send(:analyze_results)

          expect(analysis).to eq({})
        end
      end

      describe '#calculate_probability_distributions' do
        before do
          monte_carlo.instance_variable_set(:@simulation_results, [
            { total_return: 10.0, max_drawdown: 5.0 },
            { total_return: 5.0, max_drawdown: 3.0 },
            { total_return: 15.0, max_drawdown: 7.0 }
          ])
        end

        it 'calculates percentiles for returns' do
          distributions = monte_carlo.send(:calculate_probability_distributions)

          expect(distributions).to have_key(:returns)
          expect(distributions[:returns]).to have_key(:min)
          expect(distributions[:returns]).to have_key(:median)
          expect(distributions[:returns]).to have_key(:max)
        end

        it 'calculates percentiles for drawdowns' do
          distributions = monte_carlo.send(:calculate_probability_distributions)

          expect(distributions).to have_key(:drawdowns)
          expect(distributions[:drawdowns]).to have_key(:min)
          expect(distributions[:drawdowns]).to have_key(:median)
          expect(distributions[:drawdowns]).to have_key(:max)
        end

        it 'handles empty results' do
          monte_carlo.instance_variable_set(:@simulation_results, [])

          distributions = monte_carlo.send(:calculate_probability_distributions)

          expect(distributions).to eq({})
        end
      end

      describe '#calculate_confidence_intervals' do
        before do
          monte_carlo.instance_variable_set(:@simulation_results, [
            { final_capital: 110_000 },
            { final_capital: 105_000 },
            { final_capital: 115_000 }
          ])
        end

        it 'calculates confidence intervals for each level' do
          intervals = monte_carlo.send(:calculate_confidence_intervals)

          expect(intervals).to have_key(0.90)
          expect(intervals).to have_key(0.95)
          expect(intervals).to have_key(0.99)
        end

        it 'handles empty results' do
          monte_carlo.instance_variable_set(:@simulation_results, [])

          intervals = monte_carlo.send(:calculate_confidence_intervals)

          expect(intervals).to eq({})
        end
      end

      describe '#analyze_worst_cases' do
        before do
          monte_carlo.instance_variable_set(:@simulation_results, [
            { final_capital: 110_000, total_return: 10.0, max_drawdown: 5.0 },
            { final_capital: 90_000, total_return: -10.0, max_drawdown: 15.0 },
            { final_capital: 105_000, total_return: 5.0, max_drawdown: 3.0 }
          ])
        end

        it 'identifies worst case scenarios' do
          worst_cases = monte_carlo.send(:analyze_worst_cases)

          expect(worst_cases).to be_present
          expect(worst_cases).to have_key(:worst_return)
          expect(worst_cases).to have_key(:worst_drawdown)
        end

        it 'handles empty results' do
          monte_carlo.instance_variable_set(:@simulation_results, [])

          worst_cases = monte_carlo.send(:analyze_worst_cases)

          expect(worst_cases).to eq({})
        end
      end
    end
  end
end

