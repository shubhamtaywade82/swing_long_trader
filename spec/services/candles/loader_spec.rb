# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::Loader, type: :service do
  let(:instrument) { create(:instrument) }
  let(:timeframe) { '1D' }

  describe '.load_for_instrument' do
    it 'delegates to instance method' do
      allow_any_instance_of(described_class).to receive(:load_for_instrument).and_return(nil)

      described_class.load_for_instrument(
        instrument: instrument,
        timeframe: timeframe
      )

      expect_any_instance_of(described_class).to have_received(:load_for_instrument)
    end
  end

  describe '#load_for_instrument' do
    context 'when candles exist' do
      let!(:candle1) do
        create(:candle_series_record,
          instrument: instrument,
          timeframe: timeframe,
          timestamp: 2.days.ago,
          open: 100.0,
          high: 105.0,
          low: 99.0,
          close: 103.0,
          volume: 1000)
      end

      let!(:candle2) do
        create(:candle_series_record,
          instrument: instrument,
          timeframe: timeframe,
          timestamp: 1.day.ago,
          open: 103.0,
          high: 108.0,
          low: 102.0,
          close: 106.0,
          volume: 1200)
      end

      it 'loads candles from database' do
        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe
        )

        expect(series).to be_a(CandleSeries)
        expect(series.candles.size).to eq(2)
      end

      it 'converts records to CandleSeries format' do
        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe
        )

        expect(series.symbol).to eq(instrument.symbol_name)
        expect(series.interval).to eq(timeframe)
      end

      it 'converts candles correctly' do
        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe
        )

        first_candle = series.candles.first
        expect(first_candle.timestamp).to eq(candle1.timestamp)
        expect(first_candle.open).to eq(100.0)
        expect(first_candle.high).to eq(105.0)
        expect(first_candle.low).to eq(99.0)
        expect(first_candle.close).to eq(103.0)
        expect(first_candle.volume).to eq(1000)
      end

      context 'when limit is specified' do
        it 'limits the number of candles' do
          series = described_class.new.load_for_instrument(
            instrument: instrument,
            timeframe: timeframe,
            limit: 1
          )

          expect(series.candles.size).to eq(1)
        end
      end

      context 'when date range is specified' do
        it 'filters by date range' do
          series = described_class.new.load_for_instrument(
            instrument: instrument,
            timeframe: timeframe,
            from_date: 1.day.ago.to_date,
            to_date: Time.current.to_date
          )

          expect(series.candles.size).to eq(1)
          expect(series.candles.first.timestamp.to_date).to eq(1.day.ago.to_date)
        end
      end
    end

    context 'when no candles exist' do
      it 'returns nil' do
        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe
        )

        expect(series).to be_nil
      end
    end
  end

  describe '#load_latest' do
    context 'when candles exist' do
      before do
        create_list(:candle_series_record, 5,
          instrument: instrument,
          timeframe: timeframe,
          timestamp: ->(i) { i.days.ago })
      end

      it 'loads latest candles' do
        series = described_class.new.load_latest(
          instrument: instrument,
          timeframe: timeframe,
          count: 3
        )

        expect(series).to be_a(CandleSeries)
        expect(series.candles.size).to eq(3)
      end

      it 'returns candles in chronological order' do
        series = described_class.new.load_latest(
          instrument: instrument,
          timeframe: timeframe,
          count: 3
        )

        timestamps = series.candles.map(&:timestamp)
        expect(timestamps).to eq(timestamps.sort)
      end
    end

    context 'when no candles exist' do
      it 'returns nil' do
        series = described_class.new.load_latest(
          instrument: instrument,
          timeframe: timeframe,
          count: 10
        )

        expect(series).to be_nil
      end
    end
  end
end

