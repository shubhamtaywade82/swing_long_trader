# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtesting::WalkForward, type: :service do
  let(:instrument) { create(:instrument) }
  let(:instruments) { Instrument.where(id: instrument.id) }
  let(:from_date) { 200.days.ago.to_date }
  let(:to_date) { Date.today }

  describe '.call' do
    it 'delegates to instance method' do
      allow_any_instance_of(described_class).to receive(:call).and_return({ success: true })

      described_class.call(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date
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
            sharpe_ratio: 1.5
          }
        }
      )
      allow(Backtesting::DataLoader).to receive(:load_for_instruments).and_return({})
    end

    it 'generates walk-forward windows' do
      result = described_class.new(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date,
        in_sample_days: 90,
        out_of_sample_days: 30
      ).call

      expect(result[:success]).to be true
      expect(result[:windows]).to be_present
    end

    it 'runs in-sample and out-of-sample backtests' do
      result = described_class.new(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date,
        in_sample_days: 90,
        out_of_sample_days: 30
      ).call

      expect(result[:in_sample_results]).to be_present
      expect(result[:out_of_sample_results]).to be_present
    end

    context 'when window type is expanding' do
      it 'uses expanding windows' do
        result = described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          window_type: :expanding
        ).call

        expect(result[:success]).to be true
      end
    end

    context 'when window type is invalid' do
      it 'raises ArgumentError' do
        expect do
          described_class.new(
            instruments: instruments,
            from_date: from_date,
            to_date: to_date,
            window_type: :invalid
          )
        end.to raise_error(ArgumentError, /Invalid window_type/)
      end
    end

    context 'when no valid windows can be generated' do
      it 'returns error' do
        # Date range too short for windows
        short_from = 10.days.ago.to_date
        short_to = Date.today

        result = described_class.new(
          instruments: instruments,
          from_date: short_from,
          to_date: short_to,
          in_sample_days: 90,
          out_of_sample_days: 30
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('No valid windows generated')
      end
    end

    context 'when backtest fails' do
      before do
        allow(Backtesting::SwingBacktester).to receive(:call).and_return(
          { success: false, error: 'Backtest failed' }
        )
      end

      it 'skips failed backtests' do
        result = described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          in_sample_days: 90,
          out_of_sample_days: 30
        ).call

        expect(result[:success]).to be true
        expect(result[:in_sample_results]).to be_empty
      end
    end
  end
end

