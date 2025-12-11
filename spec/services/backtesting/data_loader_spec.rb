# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtesting::DataLoader, type: :service do
  let(:instrument) { create(:instrument) }
  let(:from_date) { 10.days.ago.to_date }
  let(:to_date) { Date.today }

  before do
    # Create candles for date range
    10.times do |i|
      create(:daily_candle,
        instrument: instrument,
        timestamp: i.days.ago,
        open: 100.0 + i,
        high: 105.0 + i,
        low: 99.0 + i,
        close: 103.0 + i,
        volume: 1_000_000
      )
    end
  end

  describe '#load_for_instrument' do
    it 'loads candles for instrument' do
      loader = described_class.new
      series = loader.load_for_instrument(
        instrument: instrument,
        timeframe: '1D',
        from_date: from_date,
        to_date: to_date
      )

      expect(series).not_to be_nil
      expect(series.candles).to be_any
      expect(series.interval).to eq('1D')
    end
  end

  describe '#validate_data' do
    it 'validates data with minimum candles' do
      loader = described_class.new
      data = {
        instrument.id => create_series_with_candles(60),
        create(:instrument).id => create_series_with_candles(30) # Insufficient
      }

      validated = loader.validate_data(data, min_candles: 50)

      expect(validated.size).to eq(1)
      expect(validated).to have_key(instrument.id)
    end
  end

  describe '.load_for_instruments' do
    it 'loads for multiple instruments' do
      instrument2 = create(:instrument)
      create_list(:daily_candle, 10, instrument: instrument2)

      data = described_class.load_for_instruments(
        instruments: Instrument.where(id: [instrument.id, instrument2.id]),
        timeframe: '1D',
        from_date: from_date,
        to_date: to_date
      )

      expect(data.size).to eq(2)
      expect(data).to have_key(instrument.id)
      expect(data).to have_key(instrument2.id)
    end
  end

  private

  def create_series_with_candles(count)
    series = CandleSeries.new(symbol: 'TEST', interval: '1D')
    count.times do |i|
      series.add_candle(
        Candle.new(
          timestamp: i.days.ago,
          open: 100.0,
          high: 105.0,
          low: 99.0,
          close: 103.0,
          volume: 1_000_000
        )
      )
    end
    series
  end
end

