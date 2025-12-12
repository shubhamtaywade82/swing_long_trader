# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Screeners::SwingScreener do
  let(:instrument) { create(:instrument, symbol_name: 'TEST', instrument_type: 'EQUITY') }
  let(:instruments) { Instrument.where(id: instrument.id) }

  describe '.call' do
    context 'with instruments that have candles' do
      before do
        # Create daily candles for the instrument
        create_list(:candle_series_record, 60, instrument: instrument, timeframe: '1D')

        # Call the service once for tests that use default limit
        @result = described_class.call(instruments: instruments, limit: 10)
      end

      it 'returns an array of candidates' do
        expect(@result).to be_an(Array)
      end

      it 'respects the limit parameter' do
        # This test needs a different limit, so call separately
        result = described_class.call(instruments: instruments, limit: 5)
        expect(result.size).to be <= 5
      end

      it 'returns candidates with required keys' do
        # This test needs limit: 1, so call separately
        result = described_class.call(instruments: instruments, limit: 1)
        next unless result.any?

        candidate = result.first
        expect(candidate).to have_key(:instrument_id)
        expect(candidate).to have_key(:symbol)
        expect(candidate).to have_key(:score)
        expect(candidate).to have_key(:indicators)
      end
    end

    context 'with instruments without candles' do
      it 'filters out instruments without candles' do
        instrument_no_candles = create(:instrument)
        instruments_without = Instrument.where(id: [instrument.id, instrument_no_candles.id])

        result = described_class.call(instruments: instruments_without, limit: 10)
        candidate_ids = result.map { |c| c[:instrument_id] }
        expect(candidate_ids).not_to include(instrument_no_candles.id)
      end
    end

    context 'with price filters' do
      before do
        create_list(:candle_series_record, 60, instrument: instrument, timeframe: '1D')
      end

      it 'filters instruments below minimum price' do
        allow_any_instance_of(Instrument).to receive(:ltp).and_return(10.0)

        # Mock config to require min_price of 50
        allow(AlgoConfig).to receive(:fetch).and_return({
          swing_trading: {
            screening: { min_price: 50 }
          }
        })

        result = described_class.call(instruments: instruments, limit: 10)
        # Instrument with LTP 10 should be filtered out
        expect(result.map { |c| c[:symbol] }).not_to include('TEST')
      end
    end

    context 'with insufficient candles' do
      it 'filters out instruments with less than 50 candles' do
        create_list(:candle_series_record, 30, instrument: instrument, timeframe: '1D')

        result = described_class.call(instruments: instruments, limit: 10)
        candidate_ids = result.map { |c| c[:instrument_id] }
        expect(candidate_ids).not_to include(instrument.id)
      end
    end

    context 'with universe filtering' do
      it 'loads from master_universe.yml if available' do
        universe_file = Rails.root.join('config/universe/master_universe.yml')
        allow(File).to receive(:exist?).with(universe_file).and_return(true)
        allow(YAML).to receive(:load_file).with(universe_file).and_return(['TEST', 'OTHER'])

        result = described_class.call(instruments: nil, limit: 10)
        expect(result).to be_an(Array)
      end

      it 'falls back to all equity/index instruments if universe file not found' do
        universe_file = Rails.root.join('config/universe/master_universe.yml')
        allow(File).to receive(:exist?).with(universe_file).and_return(false)

        result = described_class.call(instruments: nil, limit: 10)
        expect(result).to be_an(Array)
      end
    end
  end

  describe 'private methods' do
    let(:screener) { described_class.new(instruments: instruments) }

    context '#passes_basic_filters?' do
      it 'returns false for instruments without candles' do
        instrument_no_candles = create(:instrument)
        result = screener.send(:passes_basic_filters?, instrument_no_candles)
        expect(result).to be false
      end

      it 'returns true for instruments with candles' do
        create_list(:candle_series_record, 10, instrument: instrument, timeframe: '1D')
        allow(instrument).to receive(:ltp).and_return(100.0)

        result = screener.send(:passes_basic_filters?, instrument)
        expect(result).to be true
      end
    end
  end
end

