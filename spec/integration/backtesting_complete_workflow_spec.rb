# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Backtesting Complete Workflow Integration', type: :integration do
  let(:instrument) { create(:instrument) }
  let(:from_date) { 200.days.ago.to_date }
  let(:to_date) { Date.today }

  before do
    # Create historical candles
    200.times do |i|
      create(:candle_series_record,
        instrument: instrument,
        timeframe: '1D',
        timestamp: (199 - i).days.ago,
        open: 100.0 + i * 0.5,
        high: 105.0 + i * 0.5,
        low: 99.0 + i * 0.5,
        close: 103.0 + i * 0.5,
        volume: 1_000_000)
    end

    allow(Strategies::Swing::Engine).to receive(:call).and_return(
      {
        success: true,
        signal: {
          instrument_id: instrument.id,
          direction: :long,
          entry_price: 100.0,
          sl: 95.0,
          tp: 110.0,
          qty: 10
        }
      }
    )
    allow(AlgoConfig).to receive(:fetch).and_return({})
  end

  describe 'Complete backtesting workflow: DataLoader -> SwingBacktester -> ResultAnalyzer -> ReportGenerator' do
    context 'when all steps succeed' do
      it 'executes complete backtesting workflow' do
        # Step 1: Load data
        data = Backtesting::DataLoader.load_for_instruments(
          instruments: Instrument.where(id: instrument.id),
          timeframe: '1D',
          from_date: from_date,
          to_date: to_date
        )

        expect(data).to be_present
        expect(data[instrument.id]).to be_present

        # Step 2: Run backtest
        result = Backtesting::SwingBacktester.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
          initial_capital: 100_000
        )

        expect(result[:success]).to be true
        expect(result[:results]).to be_present

        # Step 3: Generate report
        if result[:backtest_run_id]
          backtest_run = BacktestRun.find(result[:backtest_run_id])
          report = Backtesting::ReportGenerator.generate(backtest_run)

          expect(report).to have_key(:summary)
          expect(report).to have_key(:trades_csv)
          expect(report).to have_key(:equity_curve_csv)
        end
      end
    end

    context 'when data is insufficient' do
      before do
        CandleSeriesRecord.where(instrument: instrument).delete_all
      end

      it 'returns error' do
        result = Backtesting::SwingBacktester.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date
        )

        expect(result[:success]).to be false
      end
    end

    context 'when strategy generates no signals' do
      before do
        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          { success: false, error: 'No signals' }
        )
      end

      it 'completes backtest with no trades' do
        result = Backtesting::SwingBacktester.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date
        )

        expect(result[:success]).to be true
        expect(result[:results][:total_trades]).to eq(0)
      end
    end
  end
end

