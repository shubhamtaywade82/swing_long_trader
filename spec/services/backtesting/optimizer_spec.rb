# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtesting::Optimizer, type: :service do
  let(:instrument) { create(:instrument) }
  let(:instruments) { Instrument.where(id: instrument.id) }
  let(:from_date) { 200.days.ago.to_date }
  let(:to_date) { Date.today }
  let(:parameter_ranges) do
    {
      risk_per_trade: [1.0, 2.0, 3.0],
      min_confidence: [0.6, 0.7, 0.8]
    }
  end

  describe '.call' do
    it 'delegates to instance method' do
      allow_any_instance_of(described_class).to receive(:call).and_return({ success: true })

      described_class.call(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date,
        parameter_ranges: parameter_ranges
      )

      expect_any_instance_of(described_class).to have_received(:call)
    end
  end

  describe '#call' do
    before do
      allow(Backtesting::SwingBacktester).to receive(:call).and_return(
        {
          success: true,
          results: {
            total_return: 10.0,
            sharpe_ratio: 1.5,
            max_drawdown: 5.0
          }
        }
      )
      allow(Backtesting::DataLoader).to receive(:load_for_instruments).and_return({})
    end

    it 'tests all parameter combinations' do
      result = described_class.new(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date,
        parameter_ranges: parameter_ranges
      ).call

      expect(result[:success]).to be true
      expect(result[:total_combinations_tested]).to be > 0
    end

    it 'returns best parameters' do
      result = described_class.new(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date,
        parameter_ranges: parameter_ranges
      ).call

      expect(result[:best_parameters]).to be_present
      expect(result[:best_metrics]).to be_present
    end

    it 'includes sensitivity analysis' do
      result = described_class.new(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date,
        parameter_ranges: parameter_ranges
      ).call

      expect(result[:sensitivity_analysis]).to be_present
    end

    context 'when use_walk_forward is false' do
      it 'uses simple backtest' do
        result = described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          parameter_ranges: parameter_ranges,
          use_walk_forward: false
        ).call

        expect(result[:success]).to be true
        expect(Backtesting::SwingBacktester).to have_received(:call)
      end
    end

    context 'when use_walk_forward is true' do
      before do
        allow(Backtesting::WalkForward).to receive(:call).and_return(
          {
            success: true,
            aggregated: {
              out_of_sample: {
                avg_total_return: 10.0,
                avg_sharpe_ratio: 1.5
              }
            }
          }
        )
      end

      it 'uses walk-forward analysis' do
        result = described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          parameter_ranges: parameter_ranges,
          use_walk_forward: true
        ).call

        expect(result[:success]).to be true
        expect(Backtesting::WalkForward).to have_received(:call)
      end
    end

    context 'when parameter ranges are empty' do
      it 'handles empty ranges' do
        result = described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          parameter_ranges: {}
        ).call

        expect(result[:success]).to be true
        expect(result[:total_combinations_tested]).to eq(0)
      end
    end

    context 'when all parameter tests fail' do
      before do
        allow(Backtesting::SwingBacktester).to receive(:call).and_return(
          { success: false, error: 'All tests failed' }
        )
      end

      it 'returns empty results' do
        result = described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          parameter_ranges: parameter_ranges
        ).call

        expect(result[:success]).to be true
        expect(result[:all_results]).to be_empty
      end
    end

    context 'with save_to_db option' do
      it 'saves optimization run to database' do
        result = described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          parameter_ranges: parameter_ranges
        ).call(save_to_db: true)

        expect(result[:success]).to be true
        expect(result[:optimization_run_id]).to be_present if result[:optimization_run_id]
      end
    end

    describe 'private methods' do
      let(:optimizer) do
        described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          parameter_ranges: parameter_ranges
        )
      end

      describe '#generate_combinations' do
        it 'generates all combinations from ranges' do
          ranges = {
            risk_per_trade: [1.0, 2.0],
            min_confidence: [0.6, 0.7]
          }

          combinations = optimizer.send(:generate_combinations, ranges)

          expect(combinations.size).to eq(4) # 2 * 2 = 4
          expect(combinations).to include({ risk_per_trade: 1.0, min_confidence: 0.6 })
          expect(combinations).to include({ risk_per_trade: 2.0, min_confidence: 0.7 })
        end

        it 'handles single parameter' do
          ranges = { risk_per_trade: [1.0, 2.0, 3.0] }

          combinations = optimizer.send(:generate_combinations, ranges)

          expect(combinations.size).to eq(3)
          expect(combinations).to include({ risk_per_trade: 1.0 })
          expect(combinations).to include({ risk_per_trade: 2.0 })
          expect(combinations).to include({ risk_per_trade: 3.0 })
        end

        it 'handles Range objects' do
          ranges = { risk_per_trade: (1.0..3.0).step(1.0).to_a }

          combinations = optimizer.send(:generate_combinations, ranges)

          expect(combinations.size).to eq(3)
        end

        it 'handles single value (not array)' do
          ranges = { risk_per_trade: 2.0 }

          combinations = optimizer.send(:generate_combinations, ranges)

          expect(combinations.size).to eq(1)
          expect(combinations.first[:risk_per_trade]).to eq(2.0)
        end

        it 'handles empty ranges' do
          combinations = optimizer.send(:generate_combinations, {})

          expect(combinations).to eq([{}])
        end
      end

      describe '#calculate_score' do
        it 'calculates score based on optimization metric' do
          metrics = {
            total_return: 10.0,
            sharpe_ratio: 1.5,
            max_drawdown: 5.0
          }

          score = optimizer.send(:calculate_score, metrics)

          expect(score).to eq(1.5) # Default metric is sharpe_ratio
        end

        it 'handles different optimization metrics' do
          optimizer = described_class.new(
            instruments: instruments,
            from_date: from_date,
            to_date: to_date,
            optimization_metric: :total_return
          )

          metrics = {
            total_return: 10.0,
            sharpe_ratio: 1.5
          }

          score = optimizer.send(:calculate_score, metrics)

          expect(score).to eq(10.0)
        end

        it 'handles missing metric' do
          metrics = { total_return: 10.0 }

          score = optimizer.send(:calculate_score, metrics)

          expect(score).to eq(0) # Default when metric missing
        end
      end

      describe '#calculate_sensitivity_analysis' do
        before do
          optimizer.instance_variable_set(:@results, [
            { parameters: { risk_per_trade: 1.0, min_confidence: 0.6 }, score: 1.0 },
            { parameters: { risk_per_trade: 2.0, min_confidence: 0.6 }, score: 1.5 },
            { parameters: { risk_per_trade: 1.0, min_confidence: 0.7 }, score: 1.2 }
          ])
        end

        it 'calculates sensitivity for each parameter' do
          sensitivity = optimizer.send(:calculate_sensitivity_analysis)

          expect(sensitivity).to be_a(Hash)
          expect(sensitivity).to have_key(:risk_per_trade) if sensitivity.any?
        end

        it 'handles empty results' do
          optimizer.instance_variable_set(:@results, [])

          sensitivity = optimizer.send(:calculate_sensitivity_analysis)

          expect(sensitivity).to eq({})
        end
      end

      describe '#build_backtester_options' do
        it 'builds options hash from parameters' do
          params = { risk_per_trade: 2.0, min_confidence: 0.7 }

          options = optimizer.send(:build_backtester_options, params)

          expect(options).to have_key(:risk_per_trade)
          expect(options).to have_key(:min_confidence)
        end
      end

      describe '#create_optimization_run' do
        it 'creates optimization run record' do
          run = optimizer.send(:create_optimization_run)

          expect(run).to be_a(OptimizationRun)
          expect(run.status).to eq('running')
        end
      end

      describe '#save_optimization_run' do
        it 'saves results to optimization run' do
          run = create(:optimization_run)
          result = {
            best_parameters: { risk_per_trade: 2.0 },
            best_metrics: { total_return: 10.0 }
          }

          optimizer.send(:save_optimization_run, run, result)

          run.reload
          expect(run.status).to eq('completed')
          expect(run.results).to be_present
        end
      end
    end
  end
end

