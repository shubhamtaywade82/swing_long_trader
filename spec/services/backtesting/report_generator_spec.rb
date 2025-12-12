# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtesting::ReportGenerator, type: :service do
  let(:instrument) { create(:instrument) }
  let(:backtest_run) { create(:backtest_run) }
  let(:position) { create(:backtest_position, backtest_run: backtest_run, instrument: instrument) }

  before do
    position
  end

  describe '.generate' do
    it 'delegates to instance method' do
      allow_any_instance_of(described_class).to receive(:generate_all).and_return({})

      described_class.generate(backtest_run)

      expect_any_instance_of(described_class).to have_received(:generate_all)
    end
  end

  describe '#generate_all' do
    it 'generates all report components' do
      generator = described_class.new(backtest_run)
      result = generator.generate_all

      expect(result).to have_key(:summary)
      expect(result).to have_key(:trades_csv)
      expect(result).to have_key(:equity_curve_csv)
      expect(result).to have_key(:metrics_report)
      expect(result).to have_key(:visualization_data)
    end
  end

  describe '#generate_summary' do
    it 'generates summary text' do
      generator = described_class.new(backtest_run)
      summary = generator.generate_summary

      expect(summary).to include('Backtest Run Summary')
      expect(summary).to include(backtest_run.strategy_name)
      expect(summary).to include(backtest_run.initial_capital.to_s)
    end
  end

  describe '#generate_trades_csv' do
    it 'generates CSV with position data' do
      generator = described_class.new(backtest_run)
      csv = generator.generate_trades_csv

      expect(csv).to include('Symbol')
      expect(csv).to include('Direction')
      expect(csv).to include('EntryDate')
      expect(csv).to include(instrument.symbol_name)
    end
  end

  describe '#generate_equity_curve_csv' do
    it 'generates equity curve CSV' do
      generator = described_class.new(backtest_run)
      csv = generator.generate_equity_curve_csv

      expect(csv).to include('Date')
      expect(csv).to include('Equity')
    end
  end

  describe '#generate_metrics_report' do
    it 'generates metrics report' do
      generator = described_class.new(backtest_run)
      report = generator.generate_metrics_report

      expect(report).to be_a(String)
      expect(report).to include('Performance Metrics')
    end
  end

  describe '#generate_visualization_data' do
    it 'generates visualization data' do
      generator = described_class.new(backtest_run)
      data = generator.generate_visualization_data

      expect(data).to have_key(:equity_curve)
      expect(data).to have_key(:monthly_returns)
      expect(data).to have_key(:trade_distribution)
      expect(data).to have_key(:metrics)
    end
  end

  describe 'edge cases' do
    context 'when backtest_run has no positions' do
      let(:empty_backtest_run) { create(:backtest_run) }

      before do
        allow(empty_backtest_run).to receive(:backtest_positions).and_return(BacktestPosition.none)
      end

      it 'generates empty CSV' do
        generator = described_class.new(empty_backtest_run)
        csv = generator.generate_trades_csv

        expect(csv).to include('Symbol')
        expect(csv.lines.count).to eq(2) # Header + empty
      end

      it 'generates empty equity curve' do
        generator = described_class.new(empty_backtest_run)
        csv = generator.generate_equity_curve_csv

        expect(csv).to include('Date')
      end
    end

    context 'when position has no instrument' do
      let(:position_no_instrument) do
        create(:backtest_position, backtest_run: backtest_run, instrument: nil)
      end

      before do
        position_no_instrument
      end

      it 'handles missing instrument gracefully' do
        generator = described_class.new(backtest_run)
        csv = generator.generate_trades_csv

        expect(csv).to include('N/A')
      end
    end

    context 'when metrics are missing' do
      before do
        allow(backtest_run).to receive(:metrics).and_return(nil)
      end

      it 'handles missing metrics in summary' do
        generator = described_class.new(backtest_run)
        summary = generator.generate_summary

        expect(summary).to include('N/A')
      end
    end
  end
end

