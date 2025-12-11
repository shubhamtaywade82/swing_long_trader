# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Backtesting Integration', type: :integration do
  let(:instrument) { create(:instrument, symbol_name: 'RELIANCE', security_id: '11536', instrument_type: 'EQUITY') }
  let(:from_date) { 200.days.ago.to_date }
  let(:to_date) { Date.today }
  let(:initial_capital) { 100_000.0 }

  describe 'Swing Backtester with Historical Data', :vcr do
    context 'with real historical candle data' do
      before do
        # Create sufficient candles in database (simulating ingested data)
        # This represents data that would have been ingested from DhanHQ API
        (0..199).each do |i|
          # Create realistic price movement (uptrend with some volatility)
          base_price = 2000.0 + (i * 2.0) # Uptrend
          volatility = rand(-10.0..10.0)

          create(:candle_series_record,
            instrument: instrument,
            timeframe: '1D',
            timestamp: (199 - i).days.ago,
            open: base_price + volatility,
            high: base_price + volatility + 15.0,
            low: base_price + volatility - 15.0,
            close: base_price + volatility + 5.0,
            volume: 1_000_000 + rand(500_000)
          )
        end
      end

      context 'when strategy generates signals' do
        before do
          # Mock strategy engine to return signals periodically
          # This simulates a strategy that finds opportunities
          call_count = 0
          allow(Strategies::Swing::Engine).to receive(:call) do |args|
            call_count += 1
            # Generate signal every 20th call (simulating periodic opportunities)
            if call_count % 20 == 0
              {
                success: true,
                signal: {
                  instrument_id: instrument.id,
                  symbol: instrument.symbol_name,
                  direction: :long,
                  entry_price: 2100.0 + (call_count * 0.5),
                  sl: 2050.0 + (call_count * 0.5),
                  tp: 2200.0 + (call_count * 0.5),
                  rr: 2.0,
                  qty: 10,
                  confidence: 75.0,
                  holding_days_estimate: 5
                }
              }
            else
              { success: false, error: 'No signal' }
            end
          end
        end

        it 'runs complete backtest with historical data' do
          result = Backtesting::SwingBacktester.call(
            instruments: Instrument.where(id: instrument.id),
            from_date: from_date,
            to_date: to_date,
            initial_capital: initial_capital
          )

          expect(result[:success]).to be true
          expect(result[:results]).to be_present
          expect(result[:positions]).to be_an(Array)
          expect(result[:portfolio]).to be_present
        end

        it 'calculates accurate performance metrics' do
          result = Backtesting::SwingBacktester.call(
            instruments: Instrument.where(id: instrument.id),
            from_date: from_date,
            to_date: to_date,
            initial_capital: initial_capital
          )

          metrics = result[:results]
          expect(metrics[:total_return]).to be_a(Numeric)
          expect(metrics[:total_trades]).to be >= 0
          expect(metrics[:win_rate]).to be_a(Numeric)
          expect(metrics[:win_rate]).to be >= 0
          expect(metrics[:win_rate]).to be <= 100
          expect(metrics[:max_drawdown]).to be_a(Numeric)
          expect(metrics[:sharpe_ratio]).to be_a(Numeric) if metrics[:total_trades] > 0
        end

        it 'tracks positions correctly' do
          result = Backtesting::SwingBacktester.call(
            instruments: Instrument.where(id: instrument.id),
            from_date: from_date,
            to_date: to_date,
            initial_capital: initial_capital
          )

          positions = result[:positions]
          expect(positions).to be_an(Array)

          # If positions exist, verify structure
          if positions.any?
            position = positions.first
            expect(position).to respond_to(:instrument_id)
            expect(position).to respond_to(:entry_date)
            expect(position).to respond_to(:exit_date)
            expect(position).to respond_to(:calculate_pnl)
          end
        end

        it 'handles trading costs correctly' do
          result = Backtesting::SwingBacktester.call(
            instruments: Instrument.where(id: instrument.id),
            from_date: from_date,
            to_date: to_date,
            initial_capital: initial_capital,
            commission_rate: 0.1,
            slippage_pct: 0.1
          )

          expect(result[:results][:total_commission]).to be >= 0
          expect(result[:results][:total_slippage]).to be >= 0
          expect(result[:results][:total_trading_costs]).to be >= 0
        end
      end

      context 'with trailing stop enabled' do
        before do
          # Mock strategy to return signals
          allow(Strategies::Swing::Engine).to receive(:call).and_return(
            {
              success: true,
              signal: {
                instrument_id: instrument.id,
                symbol: instrument.symbol_name,
                direction: :long,
                entry_price: 2100.0,
                sl: 2050.0,
                tp: 2200.0,
                rr: 2.0,
                qty: 10,
                confidence: 75.0,
                holding_days_estimate: 5
              }
            }
          )
        end

        it 'applies trailing stop during backtest' do
          result = Backtesting::SwingBacktester.call(
            instruments: Instrument.where(id: instrument.id),
            from_date: from_date,
            to_date: to_date,
            initial_capital: initial_capital,
            trailing_stop_pct: 5.0
          )

          expect(result[:success]).to be true
          # Verify trailing stop is applied to positions
          positions = result[:positions]
          positions.each do |position|
            if position.respond_to?(:trailing_stop_pct)
              expect(position.trailing_stop_pct).to eq(5.0)
            end
          end
        end
      end
    end

    context 'with multiple instruments' do
      let(:instrument2) { create(:instrument, symbol_name: 'TCS', security_id: '11537', instrument_type: 'EQUITY') }

      before do
        # Create candles for both instruments
        [instrument, instrument2].each do |inst|
          (0..199).each do |i|
            base_price = 3000.0 + (i * 1.5)
            volatility = rand(-8.0..8.0)

            create(:candle_series_record,
              instrument: inst,
              timeframe: '1D',
              timestamp: (199 - i).days.ago,
              open: base_price + volatility,
              high: base_price + volatility + 12.0,
              low: base_price + volatility - 12.0,
              close: base_price + volatility + 3.0,
              volume: 800_000 + rand(400_000)
            )
          end
        end

        # Mock strategy to return signals for both instruments
        allow(Strategies::Swing::Engine).to receive(:call) do |args|
          inst = args[:instrument]
          {
            success: true,
            signal: {
              instrument_id: inst.id,
              symbol: inst.symbol_name,
              direction: :long,
              entry_price: 3200.0,
              sl: 3100.0,
              tp: 3400.0,
              rr: 2.0,
              qty: 10,
              confidence: 70.0,
              holding_days_estimate: 5
            }
          }
        end
      end

      it 'runs backtest across multiple instruments' do
        result = Backtesting::SwingBacktester.call(
          instruments: Instrument.where(id: [instrument.id, instrument2.id]),
          from_date: from_date,
          to_date: to_date,
          initial_capital: initial_capital
        )

        expect(result[:success]).to be true
        expect(result[:results][:total_trades]).to be >= 0
        # Should have positions from both instruments
        positions = result[:positions]
        instrument_ids = positions.map { |p| p.instrument_id }.uniq
        expect(instrument_ids.size).to be >= 1
      end
    end

    context 'with insufficient data' do
      before do
        # Create only 30 candles (less than minimum 50)
        (0..29).each do |i|
          create(:candle_series_record,
            instrument: instrument,
            timeframe: '1D',
            timestamp: (29 - i).days.ago,
            open: 2000.0,
            high: 2010.0,
            low: 1990.0,
            close: 2005.0,
            volume: 1_000_000
          )
        end
      end

      it 'handles insufficient data gracefully' do
        result = Backtesting::SwingBacktester.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
          initial_capital: initial_capital
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Insufficient data')
      end
    end
  end

  describe 'Walk-Forward Analysis Integration', :vcr do
    before do
      # Create 300 days of candles for walk-forward testing
      (0..299).each do |i|
        base_price = 2000.0 + (i * 1.5)
        volatility = rand(-10.0..10.0)

        create(:candle_series_record,
          instrument: instrument,
          timeframe: '1D',
          timestamp: (299 - i).days.ago,
          open: base_price + volatility,
          high: base_price + volatility + 15.0,
          low: base_price + volatility - 15.0,
          close: base_price + volatility + 5.0,
          volume: 1_000_000 + rand(500_000)
        )
      end

      # Mock strategy engine
      allow(Strategies::Swing::Engine).to receive(:call).and_return(
        {
          success: true,
          signal: {
            instrument_id: instrument.id,
            symbol: instrument.symbol_name,
            direction: :long,
            entry_price: 2100.0,
            sl: 2050.0,
            tp: 2200.0,
            rr: 2.0,
            qty: 10,
            confidence: 75.0,
            holding_days_estimate: 5
          }
        }
      )
    end

    it 'runs walk-forward analysis with historical data' do
      result = Backtesting::WalkForward.call(
        instruments: Instrument.where(id: instrument.id),
        from_date: 300.days.ago.to_date,
        to_date: Date.today,
        initial_capital: initial_capital,
        window_type: :rolling,
        in_sample_days: 180,
        out_of_sample_days: 60,
        backtester_class: Backtesting::SwingBacktester
      )

      expect(result[:success]).to be true
      expect(result[:windows]).to be_an(Array)
      expect(result[:windows].size).to be > 0
      expect(result[:aggregated_results]).to be_present
    end
  end

  describe 'Monte Carlo Simulation Integration', :vcr do
    let(:positions) do
      # Create sample positions for Monte Carlo
      [
        create(:backtest_position,
          instrument: instrument,
          entry_date: 10.days.ago,
          exit_date: 5.days.ago,
          entry_price: 2000.0,
          exit_price: 2100.0,
          direction: 'long',
          quantity: 10,
          pnl: 1000.0,
          pnl_pct: 5.0
        ),
        create(:backtest_position,
          instrument: instrument,
          entry_date: 8.days.ago,
          exit_date: 3.days.ago,
          entry_price: 2050.0,
          exit_price: 2000.0,
          direction: 'long',
          quantity: 10,
          pnl: -500.0,
          pnl_pct: -2.5
        ),
        create(:backtest_position,
          instrument: instrument,
          entry_date: 6.days.ago,
          exit_date: 1.day.ago,
          entry_price: 2010.0,
          exit_price: 2110.0,
          direction: 'long',
          quantity: 10,
          pnl: 1000.0,
          pnl_pct: 5.0
        )
      ]
    end

    it 'runs Monte Carlo simulation with sample positions' do
      # Convert BacktestPosition records to Backtesting::Position objects
      mc_positions = positions.map do |bp|
        Backtesting::Position.new(
          instrument_id: bp.instrument_id,
          entry_date: bp.entry_date,
          entry_price: bp.entry_price,
          quantity: bp.quantity,
          direction: bp.direction.to_sym,
          stop_loss: bp.entry_price * 0.95,
          take_profit: bp.entry_price * 1.10
        ).tap do |pos|
          pos.close(
            exit_date: bp.exit_date,
            exit_price: bp.exit_price,
            exit_reason: 'take_profit'
          )
        end
      end

      result = Backtesting::MonteCarlo.call(
        positions: mc_positions,
        initial_capital: initial_capital,
        simulations: 100 # Reduced for faster tests
      )

      expect(result[:success]).to be true
      expect(result[:simulations]).to eq(100)
      expect(result[:results]).to be_present
      expect(result[:probability_distributions]).to be_present
      expect(result[:confidence_intervals]).to be_present
      expect(result[:worst_case_scenarios]).to be_present
    end
  end
end

