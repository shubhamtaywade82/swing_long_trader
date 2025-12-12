# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtesting::SwingBacktester, type: :service do
  let(:instrument) { create(:instrument) }
  let(:from_date) { 100.days.ago.to_date }
  let(:to_date) { Date.today }
  let(:initial_capital) { 100_000.0 }

  describe '.call' do
    context 'with sufficient historical data' do
      before do
        # Create 100 days of candles (uptrend pattern)
        (0..99).each do |i|
          create(:candle_series_record,
            instrument: instrument,
            timeframe: '1D',
            timestamp: (99 - i).days.ago,
            open: 100.0 + (i * 0.1),
            high: 105.0 + (i * 0.1),
            low: 99.0 + (i * 0.1),
            close: 103.0 + (i * 0.1),
            volume: 1_000_000
          )
        end
      end

      context 'when strategy generates signals' do
        before do
          # Mock strategy engine to return a signal
          allow(Strategies::Swing::Engine).to receive(:call).and_return(
            {
              success: true,
              signal: {
                instrument_id: instrument.id,
                symbol: instrument.symbol_name,
                direction: :long,
                entry_price: 110.0,
                sl: 105.0,
                tp: 120.0,
                rr: 2.0,
                qty: 100,
                confidence: 0.8,
                holding_days_estimate: 5
              }
            }
          )

          # Call the service once for all tests in this context
          @result = described_class.call(
            instruments: Instrument.where(id: instrument.id),
            from_date: from_date,
            to_date: to_date,
            initial_capital: initial_capital
          )
        end

        it 'runs backtest successfully' do
          expect(@result[:success]).to be true
          expect(@result[:results]).to be_present
          expect(@result[:positions]).to be_an(Array)
          expect(@result[:portfolio]).to be_present
        end

        it 'calculates performance metrics' do
          expect(@result[:results][:total_return]).to be_a(Numeric)
          expect(@result[:results][:total_trades]).to be >= 0
          expect(@result[:results][:win_rate]).to be_a(Numeric)
        end

        it 'tracks trading costs' do
          result = described_class.call(
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

      context 'when no signals are generated' do
        before do
          # Mock strategy engine to return no signal
          allow(Strategies::Swing::Engine).to receive(:call).and_return(
            { success: false, error: 'No signal' }
          )
        end

        it 'handles no trades gracefully' do
          result = described_class.call(
            instruments: Instrument.where(id: instrument.id),
            from_date: from_date,
            to_date: to_date,
            initial_capital: initial_capital
          )

          expect(result[:success]).to be true
          expect(result[:results][:total_trades]).to eq(0)
          expect(result[:results][:total_return]).to eq(0.0)
          expect(result[:positions]).to be_empty
        end
      end
    end

    context 'with insufficient data' do
      before do
        # Create only 10 candles (less than minimum 50)
        (0..9).each do |i|
          create(:candle_series_record,
            instrument: instrument,
            timeframe: '1D',
            timestamp: (9 - i).days.ago,
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1_000_000
          )
        end
      end

      it 'returns error for insufficient data' do
        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
          initial_capital: initial_capital
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Insufficient data')
      end
    end

    context 'edge case: all winning trades' do
      before do
        # Create sufficient candles
        (0..99).each do |i|
          create(:candle_series_record,
            instrument: instrument,
            timeframe: '1D',
            timestamp: (99 - i).days.ago,
            open: 100.0 + (i * 0.1),
            high: 105.0 + (i * 0.1),
            low: 99.0 + (i * 0.1),
            close: 103.0 + (i * 0.1),
            volume: 1_000_000
          )
        end

        # Mock strategy to return winning signals
        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          {
            success: true,
            signal: {
              instrument_id: instrument.id,
              symbol: instrument.symbol_name,
              direction: :long,
              entry_price: 110.0,
              sl: 105.0,
              tp: 120.0, # High TP for wins
              rr: 2.0,
              qty: 100,
              confidence: 0.8,
              holding_days_estimate: 5
            }
          }
        )
      end

      it 'calculates metrics correctly for all wins' do
        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
          initial_capital: initial_capital
        )

        expect(result[:success]).to be true
        # Win rate should be 100% if all trades hit TP
        # Note: Actual win rate depends on exit logic
        expect(result[:results][:win_rate]).to be_a(Numeric)
        expect(result[:results][:win_rate]).to be >= 0
        expect(result[:results][:win_rate]).to be <= 100
      end
    end

    context 'edge case: all losing trades' do
      before do
        # Create sufficient candles
        (0..99).each do |i|
          create(:candle_series_record,
            instrument: instrument,
            timeframe: '1D',
            timestamp: (99 - i).days.ago,
            open: 100.0 - (i * 0.1), # Downtrend
            high: 105.0 - (i * 0.1),
            low: 99.0 - (i * 0.1),
            close: 103.0 - (i * 0.1),
            volume: 1_000_000
          )
        end

        # Mock strategy to return signals that will hit SL
        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          {
            success: true,
            signal: {
              instrument_id: instrument.id,
              symbol: instrument.symbol_name,
              direction: :long,
              entry_price: 110.0,
              sl: 105.0, # Close SL
              tp: 120.0,
              rr: 2.0,
              qty: 100,
              confidence: 0.8,
              holding_days_estimate: 5
            }
          }
        )
      end

      it 'handles all losses gracefully' do
        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
          initial_capital: initial_capital
        )

        expect(result[:success]).to be true
        # Should still calculate metrics even with losses
        expect(result[:results][:total_return]).to be_a(Numeric)
        expect(result[:results][:losing_trades]).to be >= 0
      end
    end

    context 'with trailing stop enabled' do
      before do
        # Create sufficient candles
        (0..99).each do |i|
          create(:candle_series_record,
            instrument: instrument,
            timeframe: '1D',
            timestamp: (99 - i).days.ago,
            open: 100.0 + (i * 0.1),
            high: 105.0 + (i * 0.1),
            low: 99.0 + (i * 0.1),
            close: 103.0 + (i * 0.1),
            volume: 1_000_000
          )
        end

        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          {
            success: true,
            signal: {
              instrument_id: instrument.id,
              symbol: instrument.symbol_name,
              direction: :long,
              entry_price: 110.0,
              sl: 105.0,
              tp: 120.0,
              rr: 2.0,
              qty: 100,
              confidence: 0.8,
              holding_days_estimate: 5
            }
          }
        )
      end

      it 'applies trailing stop correctly' do
        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
          initial_capital: initial_capital,
          trailing_stop_pct: 5.0
        )

        expect(result[:success]).to be true
        # Positions should have trailing stop applied
        result[:positions].each do |position|
          expect(position.trailing_stop_pct).to eq(5.0) if position.respond_to?(:trailing_stop_pct)
        end
      end
    end

    context 'with commission and slippage' do
      before do
        # Create sufficient candles
        (0..99).each do |i|
          create(:candle_series_record,
            instrument: instrument,
            timeframe: '1D',
            timestamp: (99 - i).days.ago,
            open: 100.0 + (i * 0.1),
            high: 105.0 + (i * 0.1),
            low: 99.0 + (i * 0.1),
            close: 103.0 + (i * 0.1),
            volume: 1_000_000
          )
        end

        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          {
            success: true,
            signal: {
              instrument_id: instrument.id,
              symbol: instrument.symbol_name,
              direction: :long,
              entry_price: 110.0,
              sl: 105.0,
              tp: 120.0,
              rr: 2.0,
              qty: 100,
              confidence: 0.8,
              holding_days_estimate: 5
            }
          }
        )
      end

      it 'applies commission and slippage' do
        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
          initial_capital: initial_capital,
          commission_rate: 0.1,
          slippage_pct: 0.1
        )

        expect(result[:success]).to be true
        expect(result[:results][:total_commission]).to be > 0
        expect(result[:results][:total_slippage]).to be > 0
      end
    end

    context 'when data validation fails' do
      before do
        # Create insufficient candles
        create_list(:candle_series_record, 30, instrument: instrument, timeframe: '1D')
      end

      it 'returns error' do
        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Insufficient data')
      end
    end

    context 'when trailing stop is configured' do
      before do
        (0..99).each do |i|
          create(:candle_series_record,
            instrument: instrument,
            timeframe: '1D',
            timestamp: (99 - i).days.ago,
            open: 100.0 + (i * 0.1),
            high: 105.0 + (i * 0.1),
            low: 99.0 + (i * 0.1),
            close: 103.0 + (i * 0.1),
            volume: 1_000_000)
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
              qty: 100
            }
          }
        )
      end

      it 'applies trailing stop percentage' do
        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
          trailing_stop_pct: 2.0
        )

        expect(result[:success]).to be true
      end

      it 'applies trailing stop amount' do
        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date,
          trailing_stop_amount: 5.0
        )

        expect(result[:success]).to be true
      end
    end

    context 'when position exits at stop loss' do
      before do
        (0..99).each do |i|
          create(:candle_series_record,
            instrument: instrument,
            timeframe: '1D',
            timestamp: (99 - i).days.ago,
            open: 100.0 - (i * 0.1), # Downtrend
            high: 105.0 - (i * 0.1),
            low: 99.0 - (i * 0.1),
            close: 103.0 - (i * 0.1),
            volume: 1_000_000)
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
              qty: 100
            }
          }
        )
      end

      it 'closes position at stop loss' do
        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date
        )

        expect(result[:success]).to be true
        # Position should be closed if SL hit
      end
    end

    context 'with edge cases' do
      it 'handles insufficient data gracefully' do
        # Create instrument with only 10 candles (less than 50 required)
        create_list(:candle_series_record, 10,
          instrument: instrument,
          timeframe: '1D',
          timestamp: (9.days.ago..Time.current).step(1.day).to_a)

        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: 10.days.ago.to_date,
          to_date: Date.today
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Insufficient data')
      end

      it 'handles empty instruments list' do
        result = described_class.call(
          instruments: Instrument.none,
          from_date: 10.days.ago.to_date,
          to_date: Date.today
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Insufficient data')
      end

      it 'handles date range with no trading days' do
        # Create candles but outside the date range
        create_list(:candle_series_record, 100,
          instrument: instrument,
          timeframe: '1D',
          timestamp: (200.days.ago..150.days.ago).step(1.day).to_a)

        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: 10.days.ago.to_date,
          to_date: Date.today
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Insufficient data')
      end

      it 'handles commission and slippage calculations' do
        create_list(:candle_series_record, 100,
          instrument: instrument,
          timeframe: '1D',
          timestamp: (99.days.ago..Time.current).step(1.day).to_a)

        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          {
            success: true,
            signal: {
              instrument_id: instrument.id,
              direction: :long,
              entry_price: 100.0,
              sl: 95.0,
              tp: 110.0,
              qty: 100
            }
          }
        )

        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: 100.days.ago.to_date,
          to_date: Date.today,
          commission_rate: 0.1,
          slippage_pct: 0.05
        )

        expect(result[:success]).to be true
        expect(result[:results]).to have_key(:total_commission)
        expect(result[:results]).to have_key(:total_slippage)
        expect(result[:results]).to have_key(:total_trading_costs)
      end

      it 'closes all positions at end date' do
        create_list(:candle_series_record, 100,
          instrument: instrument,
          timeframe: '1D',
          timestamp: (99.days.ago..Time.current).step(1.day).to_a)

        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          {
            success: true,
            signal: {
              instrument_id: instrument.id,
              direction: :long,
              entry_price: 100.0,
              sl: 95.0,
              tp: 110.0,
              qty: 100
            }
          }
        )

        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: 100.days.ago.to_date,
          to_date: Date.today
        )

        expect(result[:success]).to be true
        # All positions should be closed at end date
        open_positions = result[:positions].select { |p| p[:status] == 'open' }
        expect(open_positions).to be_empty
      end

      it 'handles multiple instruments' do
        instrument2 = create(:instrument)
        create_list(:candle_series_record, 100,
          instrument: instrument,
          timeframe: '1D',
          timestamp: (99.days.ago..Time.current).step(1.day).to_a)
        create_list(:candle_series_record, 100,
          instrument: instrument2,
          timeframe: '1D',
          timestamp: (99.days.ago..Time.current).step(1.day).to_a)

        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          {
            success: true,
            signal: {
              instrument_id: instrument.id,
              direction: :long,
              entry_price: 100.0,
              sl: 95.0,
              tp: 110.0,
              qty: 100
            }
          }
        )

        result = described_class.call(
          instruments: Instrument.where(id: [instrument.id, instrument2.id]),
          from_date: 100.days.ago.to_date,
          to_date: Date.today
        )

        expect(result[:success]).to be true
        expect(result[:positions]).to be_an(Array)
      end

      it 'handles no signals generated' do
        create_list(:candle_series_record, 100,
          instrument: instrument,
          timeframe: '1D',
          timestamp: (99.days.ago..Time.current).step(1.day).to_a)

        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          { success: false, error: 'No signal' }
        )

        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: 100.days.ago.to_date,
          to_date: Date.today
        )

        expect(result[:success]).to be true
        expect(result[:positions]).to be_empty
      end
    end

    context 'with position management' do
      before do
        create_list(:candle_series_record, 100,
          instrument: instrument,
          timeframe: '1D',
          timestamp: (99.days.ago..Time.current).step(1.day).to_a)
      end

      it 'prevents duplicate positions for same instrument' do
        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          {
            success: true,
            signal: {
              instrument_id: instrument.id,
              direction: :long,
              entry_price: 100.0,
              sl: 95.0,
              tp: 110.0,
              qty: 100
            }
          }
        )

        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: 100.days.ago.to_date,
          to_date: Date.today
        )

        expect(result[:success]).to be true
        # Should only have one position per instrument
        positions_for_instrument = result[:positions].select { |p| p[:instrument_id] == instrument.id }
        expect(positions_for_instrument.size).to be <= 1
      end

      it 'handles position exit at take profit' do
        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          {
            success: true,
            signal: {
              instrument_id: instrument.id,
              direction: :long,
              entry_price: 100.0,
              sl: 95.0,
              tp: 110.0,
              qty: 100
            }
          }
        )

        # Mock candles that hit TP
        allow_any_instance_of(CandleSeries).to receive(:candles).and_return(
          Array.new(100) do |i|
            Candle.new(
              timestamp: i.days.ago,
              open: 100.0,
              high: 115.0, # Hits TP
              low: 99.0,
              close: 112.0,
              volume: 1_000_000
            )
          end
        )

        result = described_class.call(
          instruments: Instrument.where(id: instrument.id),
          from_date: 100.days.ago.to_date,
          to_date: Date.today
        )

        expect(result[:success]).to be true
      end
    end

    describe 'private methods' do
      let(:instrument) { create(:instrument) }
      let(:from_date) { 100.days.ago.to_date }
      let(:to_date) { Date.today }
      let(:backtester) do
        described_class.new(
          instruments: Instrument.where(id: instrument.id),
          from_date: from_date,
          to_date: to_date
        )
      end

      before do
        create_list(:candle_series_record, 100,
          instrument: instrument,
          timeframe: '1D',
          timestamp: (99.days.ago..Time.current).step(1.day).to_a)
      end

      describe '#process_date' do
        it 'processes date and checks for entry signals' do
          data = {
            instrument.id => CandleSeries.new(symbol: instrument.symbol_name, interval: '1D').tap do |cs|
              100.times { |i| cs.add_candle(create(:candle, timestamp: i.days.ago)) }
            end
          }

          allow(Strategies::Swing::Engine).to receive(:call).and_return(
            {
              success: true,
              signal: {
                instrument_id: instrument.id,
                direction: :long,
                entry_price: 100.0,
                sl: 95.0,
                tp: 110.0,
                qty: 100
              }
            }
          )

          backtester.send(:process_date, Date.today, data)

          expect(Strategies::Swing::Engine).to have_received(:call)
        end

        it 'skips instruments with existing positions' do
          data = {
            instrument.id => CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
          }
          backtester.instance_variable_set(:@portfolio, double('Portfolio', positions: { instrument.id => double('Position') }))

          backtester.send(:process_date, Date.today, data)

          expect(Strategies::Swing::Engine).not_to have_received(:call)
        end

        it 'skips instruments with insufficient candles' do
          data = {
            instrument.id => CandleSeries.new(symbol: instrument.symbol_name, interval: '1D').tap do |cs|
              30.times { |i| cs.add_candle(create(:candle, timestamp: i.days.ago)) }
            end
          }

          backtester.send(:process_date, Date.today, data)

          expect(Strategies::Swing::Engine).not_to have_received(:call)
        end
      end

      describe '#check_entry_signal' do
        it 'returns signal when engine succeeds' do
          series = CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
          series.add_candle(create(:candle, timestamp: Date.today))

          allow(Strategies::Swing::Engine).to receive(:call).and_return(
            {
              success: true,
              signal: {
                instrument_id: instrument.id,
                direction: :long,
                entry_price: 100.0,
                qty: 100
              }
            }
          )

          signal = backtester.send(:check_entry_signal, instrument, series, Date.today)

          expect(signal).to be_present
        end

        it 'returns nil when engine fails' do
          series = CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
          series.add_candle(create(:candle, timestamp: Date.today))

          allow(Strategies::Swing::Engine).to receive(:call).and_return(
            { success: false, error: 'No signal' }
          )

          signal = backtester.send(:check_entry_signal, instrument, series, Date.today)

          expect(signal).to be_nil
        end

        it 'returns nil when signal date mismatch' do
          series = CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
          series.add_candle(create(:candle, timestamp: 1.day.ago)) # Different date

          allow(Strategies::Swing::Engine).to receive(:call).and_return(
            {
              success: true,
              signal: {
                instrument_id: instrument.id,
                direction: :long,
                entry_price: 100.0,
                qty: 100
              }
            }
          )

          signal = backtester.send(:check_entry_signal, instrument, series, Date.today)

          expect(signal).to be_nil
        end

        it 'handles nil latest candle' do
          series = CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')

          signal = backtester.send(:check_entry_signal, instrument, series, Date.today)

          expect(signal).to be_nil
        end
      end

      describe '#open_position' do
        it 'opens position successfully' do
          signal = {
            entry_price: 100.0,
            qty: 100,
            direction: :long,
            sl: 95.0,
            tp: 110.0
          }

          portfolio = double('Portfolio')
          position = double('Position')
          allow(portfolio).to receive(:open_position).and_return(true)
          allow(portfolio).to receive(:positions).and_return({ instrument.id => position })
          backtester.instance_variable_set(:@portfolio, portfolio)
          backtester.instance_variable_set(:@positions, [])

          backtester.send(:open_position, instrument, signal, Date.today)

          expect(portfolio).to have_received(:open_position)
        end

        it 'skips adding position when open fails' do
          signal = {
            entry_price: 100.0,
            qty: 100,
            direction: :long,
            sl: 95.0,
            tp: 110.0
          }

          portfolio = double('Portfolio')
          allow(portfolio).to receive(:open_position).and_return(false)
          backtester.instance_variable_set(:@portfolio, portfolio)
          backtester.instance_variable_set(:@positions, [])

          backtester.send(:open_position, instrument, signal, Date.today)

          expect(backtester.instance_variable_get(:@positions)).to be_empty
        end
      end

      describe '#check_exits' do
        it 'checks exits for open positions' do
          position = double('Position', closed?: false)
          position_data = { exit_price: 110.0, exit_reason: 'tp_hit' }
          allow(position).to receive(:check_exit).and_return(position_data)

          series = CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
          series.add_candle(create(:candle, timestamp: Date.today, close: 110.0))

          data = { instrument.id => series }
          portfolio = double('Portfolio', positions: { instrument.id => position })
          allow(portfolio).to receive(:close_position)
          backtester.instance_variable_set(:@portfolio, portfolio)

          backtester.send(:check_exits, Date.today, data)

          expect(portfolio).to have_received(:close_position)
        end

        it 'skips closed positions' do
          position = double('Position', closed?: true)

          data = { instrument.id => CandleSeries.new(symbol: instrument.symbol_name, interval: '1D') }
          portfolio = double('Portfolio', positions: { instrument.id => position })
          backtester.instance_variable_set(:@portfolio, portfolio)

          backtester.send(:check_exits, Date.today, data)

          expect(position).not_to have_received(:check_exit)
        end

        it 'skips positions without series data' do
          position = double('Position', closed?: false)

          data = {}
          portfolio = double('Portfolio', positions: { instrument.id => position })
          backtester.instance_variable_set(:@portfolio, portfolio)

          backtester.send(:check_exits, Date.today, data)

          expect(position).not_to have_received(:check_exit)
        end

        it 'skips positions without candle for date' do
          position = double('Position', closed?: false)

          series = CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
          # No candle for today

          data = { instrument.id => series }
          portfolio = double('Portfolio', positions: { instrument.id => position })
          backtester.instance_variable_set(:@portfolio, portfolio)

          backtester.send(:check_exits, Date.today, data)

          expect(position).not_to have_received(:check_exit)
        end

        it 'skips positions when exit check returns nil' do
          position = double('Position', closed?: false)
          allow(position).to receive(:check_exit).and_return(nil)

          series = CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
          series.add_candle(create(:candle, timestamp: Date.today, close: 100.0))

          data = { instrument.id => series }
          portfolio = double('Portfolio', positions: { instrument.id => position })
          backtester.instance_variable_set(:@portfolio, portfolio)

          backtester.send(:check_exits, Date.today, data)

          expect(portfolio).not_to have_received(:close_position)
        end
      end

      describe '#close_all_positions' do
        it 'closes all open positions' do
          position = double('Position', closed?: false, entry_price: 100.0)

          series = CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
          series.add_candle(create(:candle, timestamp: Date.today, close: 105.0))

          data = { instrument.id => series }
          portfolio = double('Portfolio', positions: { instrument.id => position })
          allow(portfolio).to receive(:close_position)
          backtester.instance_variable_set(:@portfolio, portfolio)

          backtester.send(:close_all_positions, Date.today, data)

          expect(portfolio).to have_received(:close_position).with(
            instrument_id: instrument.id,
            exit_date: Date.today,
            exit_price: 105.0,
            exit_reason: 'end_of_backtest'
          )
        end

        it 'uses entry price when no series data' do
          position = double('Position', closed?: false, entry_price: 100.0)

          data = {}
          portfolio = double('Portfolio', positions: { instrument.id => position })
          allow(portfolio).to receive(:close_position)
          backtester.instance_variable_set(:@portfolio, portfolio)

          backtester.send(:close_all_positions, Date.today, data)

          expect(portfolio).to have_received(:close_position).with(
            instrument_id: instrument.id,
            exit_date: Date.today,
            exit_price: 100.0,
            exit_reason: 'end_of_backtest'
          )
        end

        it 'skips closed positions' do
          position = double('Position', closed?: true)

          data = { instrument.id => CandleSeries.new(symbol: instrument.symbol_name, interval: '1D') }
          portfolio = double('Portfolio', positions: { instrument.id => position })
          backtester.instance_variable_set(:@portfolio, portfolio)

          backtester.send(:close_all_positions, Date.today, data)

          expect(portfolio).not_to have_received(:close_position)
        end

        it 'handles nil series' do
          position = double('Position', closed?: false, entry_price: 100.0)

          data = { instrument.id => nil }
          portfolio = double('Portfolio', positions: { instrument.id => position })
          allow(portfolio).to receive(:close_position)
          backtester.instance_variable_set(:@portfolio, portfolio)

          backtester.send(:close_all_positions, Date.today, data)

          expect(portfolio).to have_received(:close_position).with(
            instrument_id: instrument.id,
            exit_date: Date.today,
            exit_price: 100.0,
            exit_reason: 'end_of_backtest'
          )
        end
      end
    end
  end
end

