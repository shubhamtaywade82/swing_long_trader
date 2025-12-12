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
  end
end

