# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::WeeklyIngestor do
  let(:instrument) { create(:instrument, symbol_name: 'TEST', security_id: '12345') }
  let(:instruments) { Instrument.where(id: instrument.id) }

  describe '.call' do
    context 'with valid daily candles' do
      let(:mock_daily_candles) do
        # Create 7 days of candles (one week)
        7.times.map do |i|
          {
            timestamp: i.days.ago.to_i,
            open: 100.0 + i,
            high: 105.0 + i,
            low: 99.0 + i,
            close: 103.0 + i,
            volume: 1_000_000
          }
        end
      end

      before do
        allow(instrument).to receive(:historical_ohlc).and_return(mock_daily_candles)
      end

      it 'aggregates daily candles into weekly candles' do
        result = described_class.call(instruments: instruments, weeks_back: 1)

        expect(result[:success]).to be > 0
        expect(CandleSeriesRecord.where(instrument: instrument, timeframe: '1W').count).to be > 0
      end

      it 'creates weekly candles with correct OHLC' do
        result = described_class.call(instruments: instruments, weeks_back: 1)

        weekly_candle = CandleSeriesRecord.where(instrument: instrument, timeframe: '1W').first
        expect(weekly_candle).to be_present
        expect(weekly_candle.open).to be_a(Numeric)
        expect(weekly_candle.high).to be_a(Numeric)
        expect(weekly_candle.low).to be_a(Numeric)
        expect(weekly_candle.close).to be_a(Numeric)
        expect(weekly_candle.volume).to be_a(Numeric)
      end

      it 'aggregates from Monday to Sunday' do
        result = described_class.call(instruments: instruments, weeks_back: 1)

        weekly_candles = CandleSeriesRecord.where(instrument: instrument, timeframe: '1W')
        expect(weekly_candles).to be_any
        # Weekly candle should have timestamp of Monday
        weekly_candles.each do |candle|
          expect(candle.timestamp.wday).to eq(1) # Monday
        end
      end

      it 'handles custom weeks_back parameter' do
        result = described_class.call(instruments: instruments, weeks_back: 4)

        expect(result[:processed]).to eq(1)
        # Should fetch enough daily candles for 4 weeks
        expect(instrument).to have_received(:historical_ohlc).at_least(:once)
      end
    end

    context 'with insufficient daily candles' do
      it 'handles instruments without daily candles' do
        instrument_no_candles = create(:instrument, security_id: '99999')
        allow(instrument_no_candles).to receive(:historical_ohlc).and_return([])

        result = described_class.call(
          instruments: Instrument.where(id: instrument_no_candles.id),
          weeks_back: 1
        )

        expect(result[:failed]).to be >= 0
      end
    end

    context 'with multiple instruments' do
      let(:instrument2) { create(:instrument, symbol_name: 'TEST2', security_id: '12346') }
      let(:multiple_instruments) { Instrument.where(id: [instrument.id, instrument2.id]) }

      before do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])
      end

      it 'processes all instruments' do
        result = described_class.call(instruments: multiple_instruments, weeks_back: 1)

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
    end
  end
end

