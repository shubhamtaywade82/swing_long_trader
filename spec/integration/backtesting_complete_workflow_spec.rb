# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Backtesting Complete Workflow", type: :integration do
  let(:instrument) { create(:instrument) }
  let(:from_date) { 100.days.ago.to_date }
  let(:to_date) { Time.zone.today }

  before do
    # Create historical candles
    100.times do |i|
      create(:candle_series_record,
             instrument: instrument,
             timeframe: "1D",
             timestamp: (99 - i).days.ago,
             open: 100.0 + (i * 0.1),
             high: 105.0 + (i * 0.1),
             low: 99.0 + (i * 0.1),
             close: 103.0 + (i * 0.1),
             volume: 1_000_000)
    end

    # Mock strategy engine
    allow(Strategies::Swing::Engine).to receive(:call).and_return(
      {
        success: true,
        signal: {
          instrument_id: instrument.id,
          direction: :long,
          entry_price: 110.0,
          sl: 105.0,
          tp: 120.0,
          qty: 100,
        },
      },
    )
  end

  describe "Complete workflow: DataLoader -> SwingBacktester -> ResultAnalyzer -> ReportGenerator" do
    context "when all steps succeed" do
      it "executes complete backtesting workflow" do
        # Step 1: Load data
        data = Backtesting::DataLoader.load_for_instruments(
          instruments: Instrument.where(id: instrument.id),
          timeframe: "1D",
          from_date: from_date,
          to_date: to_date,
        )

        expect(data).to be_present
        expect(data[instrument.id]).to be_present

        # Step 2: Run backtest
        result = Backtesting::SwingBacktester.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
          initial_capital: 100_000,
          risk_per_trade: 2.0,
        )

        expect(result[:success]).to be true
        expect(result[:results]).to be_present
        expect(result[:positions]).to be_an(Array)
        expect(result[:portfolio]).to be_present

        # Step 3: Analyze results
        analyzer = Backtesting::ResultAnalyzer.new(
          positions: result[:positions],
          initial_capital: 100_000,
          final_capital: result[:portfolio].current_equity,
        )

        analysis = analyzer.analyze

        expect(analysis).to have_key(:total_return)
        expect(analysis).to have_key(:max_drawdown)
        expect(analysis).to have_key(:win_rate)
        expect(analysis).to have_key(:sharpe_ratio)

        # Step 4: Generate report
        backtest_run = create(:backtest_run,
                              instrument: instrument,
                              from_date: from_date,
                              to_date: to_date,
                              initial_capital: 100_000,
                              final_capital: result[:portfolio].current_equity)

        report_generator = Backtesting::ReportGenerator.new(backtest_run: backtest_run)
        summary = report_generator.generate_summary

        expect(summary).to be_present
        expect(summary).to have_key(:total_return)
        expect(summary).to have_key(:max_drawdown)
      end
    end

    context "when data loading fails" do
      it "handles insufficient data gracefully" do
        # Create only 10 candles (less than 50 required)
        CandleSeriesRecord.where(instrument: instrument).destroy_all
        create_list(:candle_series_record, 10,
                    instrument: instrument,
                    timeframe: "1D",
                    timestamp: (9.days.ago..Time.current).step(1.day).to_a)

        result = Backtesting::SwingBacktester.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: 10.days.ago.to_date,
          to_date: Time.zone.today,
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include("Insufficient data")
      end
    end

    context "when no signals are generated" do
      before do
        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          { success: false, error: "No signal" },
        )
      end

      it "completes backtest with no positions" do
        result = Backtesting::SwingBacktester.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
        )

        expect(result[:success]).to be true
        expect(result[:positions]).to be_empty
      end
    end

    context "when positions are closed at end date" do
      it "closes all positions at end of backtest" do
        result = Backtesting::SwingBacktester.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
        )

        expect(result[:success]).to be true
        # All positions should be closed
        open_positions = result[:positions].select { |p| p[:status] == "open" }
        expect(open_positions).to be_empty
      end
    end

    context "with multiple instruments" do
      let(:instrument2) { create(:instrument) }

      before do
        # Create candles for second instrument
        100.times do |i|
          create(:candle_series_record,
                 instrument: instrument2,
                 timeframe: "1D",
                 timestamp: (99 - i).days.ago,
                 open: 50.0 + (i * 0.05),
                 high: 52.0 + (i * 0.05),
                 low: 49.0 + (i * 0.05),
                 close: 51.0 + (i * 0.05),
                 volume: 500_000)
        end

        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          {
            success: true,
            signal: {
              instrument_id: instrument.id,
              direction: :long,
              entry_price: 110.0,
              sl: 105.0,
              tp: 120.0,
              qty: 100,
            },
          },
          {
            success: true,
            signal: {
              instrument_id: instrument2.id,
              direction: :long,
              entry_price: 55.0,
              sl: 52.0,
              tp: 60.0,
              qty: 200,
            },
          },
        )
      end

      it "backtests multiple instruments" do
        result = Backtesting::SwingBacktester.call(
          instruments: Instrument.where(id: [instrument.id, instrument2.id]),
          from_date: from_date,
          to_date: to_date,
        )

        expect(result[:success]).to be true
        expect(result[:positions]).to be_an(Array)
      end
    end

    context "with commission and slippage" do
      it "includes trading costs in results" do
        result = Backtesting::SwingBacktester.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
          commission_rate: 0.1,
          slippage_pct: 0.05,
        )

        expect(result[:success]).to be true
        expect(result[:results]).to have_key(:total_commission)
        expect(result[:results]).to have_key(:total_slippage)
        expect(result[:results]).to have_key(:total_trading_costs)
      end
    end
  end
end
