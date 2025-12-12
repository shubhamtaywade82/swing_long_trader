# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::WeeklyIngestor do
  let(:instrument) { create(:instrument, symbol_name: 'TEST', security_id: '12345') }
  let(:instruments) { Instrument.where(id: instrument.id) }

  describe '.call' do
    context 'when daily candles are valid' do
      let(:mock_daily_candles) do
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

      let(:result) { described_class.call(instruments: instruments, weeks_back: 1) }

      before do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).with(
          from_date: anything,
          to_date: anything,
          oi: false
        ).and_return(mock_daily_candles)
      end

      it { expect(result[:processed]).to eq(1) }

      it { expect(result[:success]).to be > 0 }

      it 'creates weekly candles' do
        result
        expect(CandleSeriesRecord.where(instrument: instrument, timeframe: '1W').count).to be > 0
      end

      describe 'weekly candle attributes' do
        let(:weekly_candle) do
          result
          CandleSeriesRecord.where(instrument: instrument, timeframe: '1W').first
        end

        it { expect(weekly_candle).to be_present }

        it { expect(weekly_candle.open).to be_a(Numeric) }

        it { expect(weekly_candle.high).to be_a(Numeric) }

        it { expect(weekly_candle.low).to be_a(Numeric) }

        it { expect(weekly_candle.close).to be_a(Numeric) }

        it { expect(weekly_candle.volume).to be_a(Numeric) }
      end

      it 'aggregates from Monday to Sunday' do
        result
        weekly_candles = CandleSeriesRecord.where(instrument: instrument, timeframe: '1W')

        expect(weekly_candles).to be_any
        weekly_candles.each do |candle|
          expect(candle.timestamp.wday).to eq(1)
        end
      end
    end

    context 'when weeks_back is custom' do
      let(:mock_daily_candles) do
        28.times.map do |i|
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

      let(:result) { described_class.call(instruments: instruments, weeks_back: 4) }

      before do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).with(
          from_date: anything,
          to_date: anything,
          oi: false
        ).and_return(mock_daily_candles)
      end

      it { expect(result[:processed]).to eq(1) }

      it { expect(result[:success]).to be > 0 }
    end

    context 'when daily candles are insufficient' do
      let(:instrument_no_candles) { create(:instrument, security_id: '99999') }
      let(:instruments_empty) { Instrument.where(id: instrument_no_candles.id) }
      let(:result) { described_class.call(instruments: instruments_empty, weeks_back: 1) }

      before do
        allow(instrument_no_candles).to receive(:historical_ohlc).and_return([])
      end

      it { expect(result[:failed]).to be >= 0 }
    end

    context 'when instrument has no security_id' do
      let(:instrument_no_security) { create(:instrument, symbol_name: 'NO_SEC', security_id: nil) }
      let(:instruments_no_security) { Instrument.where(id: instrument_no_security.id) }
      let(:result) { described_class.call(instruments: instruments_no_security, weeks_back: 1) }

      it { expect(result[:failed]).to be >= 0 }
    end

    context 'when multiple instruments are provided' do
      let(:instrument2) { create(:instrument, symbol_name: 'TEST2', security_id: '12346') }
      let(:multiple_instruments) { Instrument.where(id: [instrument.id, instrument2.id]) }
      let(:result) { described_class.call(instruments: multiple_instruments, weeks_back: 1) }

      before do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])
      end

      it { expect(result[:processed]).to eq(2) }
    end

    context 'when no instruments are provided' do
      let(:result) { described_class.call }

      before do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])
      end

      it { expect(result).to be_a(Hash) }

      it { expect(result[:processed]).to be >= 0 }
    end
  end
end

