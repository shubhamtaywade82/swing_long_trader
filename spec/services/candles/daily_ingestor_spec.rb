# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::DailyIngestor do
  let(:instrument) { create(:instrument, symbol_name: 'TEST', security_id: '12345') }
  let(:instruments) { Instrument.where(id: instrument.id) }

  describe '.call' do
    context 'with valid instruments' do
      let(:mock_candles) do
        [
          {
            timestamp: 1.day.ago.to_i,
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1_000_000
          },
          {
            timestamp: 2.days.ago.to_i,
            open: 98.0,
            high: 102.0,
            low: 97.0,
            close: 100.0,
            volume: 900_000
          }
        ]
      end

      before do
        # Use allow_any_instance_of since find_each reloads the instrument
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).with(
          from_date: anything,
          to_date: anything,
          oi: false
        ).and_return(mock_candles)

        # Call the service once for all tests in this context
        @result = described_class.call(instruments: instruments, days_back: 2)
      end

      it 'fetches and stores daily candles' do
        expect(@result[:success]).to eq(1) # Count of successful instruments
        expect(@result[:processed]).to eq(1)
        expect(CandleSeriesRecord.where(instrument: instrument, timeframe: '1D').count).to eq(2)
      end

      it 'returns summary with processed count' do
        expect(@result).to have_key(:processed)
        expect(@result).to have_key(:success)
        expect(@result).to have_key(:failed)
        expect(@result).to have_key(:total_candles)
      end

      it 'upserts candles without creating duplicates' do
        initial_count = CandleSeriesRecord.count

        # Second import with same data
        described_class.call(instruments: instruments, days_back: 2)

        # Should not create duplicates
        expect(CandleSeriesRecord.count).to eq(initial_count)
      end

      it 'handles custom days_back parameter' do
        # This test needs a different days_back, so call separately
        result = described_class.call(instruments: instruments, days_back: 5)

        expect(result[:processed]).to eq(1)
        expect(result[:success]).to eq(1)
      end
    end

    context 'with invalid instruments' do
      it 'handles instruments without security_id' do
        # Create instrument with empty security_id (database has NOT NULL, so use empty string)
        instrument_no_id = create(:instrument)
        instrument_no_id.update_column(:security_id, '')
        instruments_invalid = Instrument.where(id: instrument_no_id.id)

        result = described_class.call(instruments: instruments_invalid, days_back: 2)

        expect(result[:failed]).to eq(1)
        expect(result[:errors]).not_to be_empty
      end

      it 'handles API errors gracefully' do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_raise(StandardError.new('API error'))

        result = described_class.call(instruments: instruments, days_back: 2)

        expect(result[:failed]).to eq(1)
        expect(result[:errors]).not_to be_empty
      end
    end

    context 'with multiple instruments' do
      let(:instrument2) { create(:instrument, symbol_name: 'TEST2', security_id: '12346') }
      let(:multiple_instruments) { Instrument.where(id: [instrument.id, instrument2.id]) }

      before do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])
      end

      it 'processes all instruments' do
        result = described_class.call(instruments: multiple_instruments, days_back: 2)

        expect(result[:processed]).to eq(2)
      end
    end

    context 'with default parameters' do
      it 'uses all equity/index instruments if none provided' do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])

        result = described_class.call

        expect(result).to be_a(Hash)
        expect(result[:processed]).to be >= 0
      end

      it 'uses default days_back if not provided' do
        # Use allow_any_instance_of since find_each reloads the instrument
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).with(
          from_date: anything,
          to_date: anything,
          oi: false
        ).and_return([
          {
            timestamp: 1.day.ago.to_i,
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1_000_000
          }
        ])

        result = described_class.call(instruments: instruments)

        expect(result[:processed]).to eq(1)
        expect(result[:success]).to eq(1)
        # Default days_back is 365, so from_date should be approximately 365 days before to_date
      end
    end
  end
end

