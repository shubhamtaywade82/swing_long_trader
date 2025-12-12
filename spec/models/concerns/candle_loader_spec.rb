# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandleLoader, type: :concern do
  let(:instrument) { create(:instrument) }

  describe '#load_daily_candles' do
    before do
      allow(Candles::Loader).to receive(:load_for_instrument).and_return(
        CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
      )
    end

    it 'delegates to Candles::Loader' do
      result = instrument.load_daily_candles

      expect(Candles::Loader).to have_received(:load_for_instrument).with(
        instrument: instrument,
        timeframe: '1D',
        limit: nil,
        from_date: nil,
        to_date: nil
      )
      expect(result).to be_a(CandleSeries)
    end

    it 'passes limit parameter' do
      instrument.load_daily_candles(limit: 100)

      expect(Candles::Loader).to have_received(:load_for_instrument).with(
        instrument: instrument,
        timeframe: '1D',
        limit: 100,
        from_date: nil,
        to_date: nil
      )
    end

    it 'passes date range parameters' do
      from_date = 30.days.ago.to_date
      to_date = Date.today

      instrument.load_daily_candles(from_date: from_date, to_date: to_date)

      expect(Candles::Loader).to have_received(:load_for_instrument).with(
        instrument: instrument,
        timeframe: '1D',
        limit: nil,
        from_date: from_date,
        to_date: to_date
      )
    end
  end

  describe '#load_weekly_candles' do
    before do
      allow(Candles::Loader).to receive(:load_for_instrument).and_return(
        CandleSeries.new(symbol: instrument.symbol_name, interval: '1W')
      )
    end

    it 'delegates to Candles::Loader with weekly timeframe' do
      result = instrument.load_weekly_candles

      expect(Candles::Loader).to have_received(:load_for_instrument).with(
        instrument: instrument,
        timeframe: '1W',
        limit: nil,
        from_date: nil,
        to_date: nil
      )
      expect(result).to be_a(CandleSeries)
    end
  end

  describe '#load_candles' do
    before do
      allow(Candles::Loader).to receive(:load_latest).and_return(
        CandleSeries.new(symbol: instrument.symbol_name, interval: '15')
      )
    end

    it 'delegates to Candles::Loader.load_latest' do
      result = instrument.load_candles(timeframe: '15', count: 50)

      expect(Candles::Loader).to have_received(:load_latest).with(
        instrument: instrument,
        timeframe: '15',
        count: 50
      )
      expect(result).to be_a(CandleSeries)
    end

    it 'uses default count of 100' do
      instrument.load_candles(timeframe: '1D')

      expect(Candles::Loader).to have_received(:load_latest).with(
        instrument: instrument,
        timeframe: '1D',
        count: 100
      )
    end
  end

  describe '#has_candles?' do
    context 'when candles exist' do
      before do
        create(:candle_series_record, instrument: instrument, timeframe: '1D')
      end

      it 'returns true' do
        expect(instrument.has_candles?(timeframe: '1D')).to be true
      end
    end

    context 'when no candles exist' do
      it 'returns false' do
        expect(instrument.has_candles?(timeframe: '1D')).to be false
      end
    end
  end

  describe '#latest_candle_timestamp' do
    context 'when candles exist' do
      let(:timestamp) { 1.day.ago }

      before do
        create(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: timestamp)
      end

      it 'returns latest timestamp' do
        result = instrument.latest_candle_timestamp(timeframe: '1D')

        expect(result).to be_within(1.second).of(timestamp)
      end
    end

    context 'when no candles exist' do
      it 'returns nil' do
        expect(instrument.latest_candle_timestamp(timeframe: '1D')).to be_nil
      end
    end
  end
end

