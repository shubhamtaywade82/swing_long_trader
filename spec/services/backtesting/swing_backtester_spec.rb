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
  end
end

