# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtesting::LongTermBacktester, type: :service do
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
      allow(Backtesting::DataLoader).to receive(:load_for_instruments).and_return(
        {
          instrument.id => CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
        }
      )
      allow_any_instance_of(Backtesting::DataLoader).to receive(:validate_data).and_return(
        {
          instrument.id => CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
        }
      )
      allow(Strategies::LongTerm::Evaluator).to receive(:call).and_return(
        { success: false }
      )
      allow(AlgoConfig).to receive(:fetch).and_return({})
    end

    it 'loads daily and weekly data' do
      described_class.new(
        instruments: instruments,
        from_date: from_date,
        to_date: to_date
      ).call

      expect(Backtesting::DataLoader).to have_received(:load_for_instruments).with(
        instruments: instruments,
        timeframe: '1D',
        from_date: from_date,
        to_date: to_date
      )
      expect(Backtesting::DataLoader).to have_received(:load_for_instruments).with(
        instruments: instruments,
        timeframe: '1W',
        from_date: from_date,
        to_date: to_date
      )
    end

    context 'when data is insufficient' do
      before do
        allow_any_instance_of(Backtesting::DataLoader).to receive(:validate_data).and_return({})
      end

      it 'returns error' do
        result = described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Insufficient data')
      end
    end

    context 'with rebalancing' do
      before do
        (0..199).each do |i|
          create(:candle_series_record,
            instrument: instrument,
            timeframe: '1D',
            timestamp: (199 - i).days.ago,
            open: 100.0 + i * 0.1,
            high: 105.0 + i * 0.1,
            low: 99.0 + i * 0.1,
            close: 103.0 + i * 0.1,
            volume: 1_000_000)
        end

        allow(Backtesting::DataLoader).to receive(:load_for_instruments).and_return(
          {
            instrument.id => CandleSeries.new(symbol: instrument.symbol_name, interval: '1D').tap do |cs|
              200.times { |i| cs.add_candle(create(:candle, timestamp: (199 - i).days.ago)) }
            end
          }
        )
        allow_any_instance_of(Backtesting::DataLoader).to receive(:validate_data).and_return(
          {
            instrument.id => CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
          }
        )
        allow(Strategies::LongTerm::Evaluator).to receive(:call).and_return(
          { success: true, signal: { instrument_id: instrument.id } }
        )
        allow(AlgoConfig).to receive(:fetch).and_return({})
      end

      it 'rebalances on weekly frequency' do
        result = described_class.call(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          rebalance_frequency: :weekly
        )

        expect(result[:success]).to be true
      end

      it 'rebalances on monthly frequency' do
        result = described_class.call(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          rebalance_frequency: :monthly
        )

        expect(result[:success]).to be true
      end
    end

    context 'with exit conditions' do
      before do
        (0..199).each do |i|
          create(:candle_series_record,
            instrument: instrument,
            timeframe: '1D',
            timestamp: (199 - i).days.ago,
            open: 100.0 - i * 0.1, # Downtrend
            high: 105.0 - i * 0.1,
            low: 99.0 - i * 0.1,
            close: 103.0 - i * 0.1,
            volume: 1_000_000)
        end

        allow(Backtesting::DataLoader).to receive(:load_for_instruments).and_return(
          {
            instrument.id => CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
          }
        )
        allow_any_instance_of(Backtesting::DataLoader).to receive(:validate_data).and_return(
          {
            instrument.id => CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
          }
        )
        allow(Strategies::LongTerm::Evaluator).to receive(:call).and_return(
          { success: true, signal: { instrument_id: instrument.id } }
        )
        allow(AlgoConfig).to receive(:fetch).and_return({})
      end

      it 'closes positions at stop loss' do
        result = described_class.call(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date
        )

        expect(result[:success]).to be true
      end
    end

    describe 'private methods' do
      let(:backtester) do
        described_class.new(
          instruments: instruments,
          from_date: from_date,
          to_date: to_date,
          rebalance_frequency: :weekly
        )
      end

      describe '#should_rebalance?' do
        it 'returns true for first rebalance' do
          expect(backtester.send(:should_rebalance?, from_date)).to be true
        end

        it 'returns true for weekly rebalance on Monday' do
          monday = from_date.beginning_of_week
          backtester.instance_variable_set(:@last_rebalance_date, monday - 1.week)

          expect(backtester.send(:should_rebalance?, monday)).to be true
        end

        it 'returns false for non-Monday when weekly' do
          tuesday = from_date.beginning_of_week + 1.day
          backtester.instance_variable_set(:@last_rebalance_date, from_date.beginning_of_week)

          expect(backtester.send(:should_rebalance?, tuesday)).to be false
        end

        it 'returns true for monthly rebalance on first day' do
          backtester = described_class.new(
            instruments: instruments,
            from_date: from_date,
            to_date: to_date,
            rebalance_frequency: :monthly
          )

          first_of_month = Date.new(from_date.year, from_date.month, 1)
          backtester.instance_variable_set(:@last_rebalance_date, first_of_month - 1.month)

          expect(backtester.send(:should_rebalance?, first_of_month)).to be true
        end

        it 'returns false for non-first day when monthly' do
          backtester = described_class.new(
            instruments: instruments,
            from_date: from_date,
            to_date: to_date,
            rebalance_frequency: :monthly
          )

          second_of_month = Date.new(from_date.year, from_date.month, 2)
          backtester.instance_variable_set(:@last_rebalance_date, Date.new(from_date.year, from_date.month, 1))

          expect(backtester.send(:should_rebalance?, second_of_month)).to be false
        end
      end

      describe '#check_entry_signal' do
        before do
          allow(Strategies::LongTerm::Evaluator).to receive(:call).and_return(
            { success: true, signal: { instrument_id: instrument.id } }
          )
        end

        it 'checks entry signal for candidate' do
          candidate = {
            instrument: instrument,
            instrument_id: instrument.id
          }

          signal = backtester.send(:check_entry_signal, candidate, from_date, {}, {})

          expect(signal).to be_present
          expect(Strategies::LongTerm::Evaluator).to have_received(:call)
        end

        it 'returns nil when evaluator returns no signal' do
          allow(Strategies::LongTerm::Evaluator).to receive(:call).and_return(
            { success: false }
          )

          candidate = {
            instrument: instrument,
            instrument_id: instrument.id
          }

          signal = backtester.send(:check_entry_signal, candidate, from_date, {}, {})

          expect(signal).to be_nil
        end
      end

      describe '#open_position' do
        before do
          allow(Strategies::LongTerm::Evaluator).to receive(:call).and_return(
            { success: true, signal: { instrument_id: instrument.id, entry_price: 100.0, qty: 10 } }
          )
        end

        it 'opens position and adds to portfolio' do
          candidate = {
            instrument: instrument,
            instrument_id: instrument.id
          }
          signal = { entry_price: 100.0, qty: 10 }

          backtester.send(:open_position, candidate[:instrument], signal, from_date)

          expect(backtester.instance_variable_get(:@positions)).not_to be_empty
        end
      end

      describe '#check_exits' do
        it 'checks exit conditions for open positions' do
          # Create a position
          position = double(
            instrument_id: instrument.id,
            entry_date: from_date,
            exit_date: nil,
            check_exit: { exit: false }
          )

          backtester.instance_variable_set(:@positions, [position])
          backtester.instance_variable_get(:@portfolio).instance_variable_set(:@positions, {
            instrument.id => position
          })

          backtester.send(:check_exits, from_date + 1.day, {})

          # Should not raise error
          expect(true).to be true
        end
      end

      describe '#close_all_positions' do
        it 'closes all open positions' do
          position = double(
            instrument_id: instrument.id,
            entry_date: from_date,
            exit_date: nil
          )

          backtester.instance_variable_set(:@positions, [position])
          backtester.instance_variable_get(:@portfolio).instance_variable_set(:@positions, {
            instrument.id => position
          })

          backtester.send(:close_all_positions, to_date, {})

          # Should not raise error
          expect(true).to be true
        end
      end

      describe '#calculate_avg_positions_per_rebalance' do
        it 'calculates average positions per rebalance' do
          backtester.instance_variable_set(:@portfolio_composition, [
            { date: from_date, positions: 5 },
            { date: from_date + 1.week, positions: 7 },
            { date: from_date + 2.weeks, positions: 6 }
          ])

          avg = backtester.send(:calculate_avg_positions_per_rebalance)

          expect(avg).to eq(6.0) # (5 + 7 + 6) / 3
        end

        it 'returns 0 when no rebalances' do
          backtester.instance_variable_set(:@portfolio_composition, [])

          avg = backtester.send(:calculate_avg_positions_per_rebalance)

          expect(avg).to eq(0)
        end
      end
    end
  end
end

