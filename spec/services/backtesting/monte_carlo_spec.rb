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
  end
end

