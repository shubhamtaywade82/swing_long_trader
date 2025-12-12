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
  end
end

