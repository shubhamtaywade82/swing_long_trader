# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandleSeriesRecord, type: :model do
  let(:instrument) { create(:instrument) }

  describe 'validations' do
    it 'is valid with valid attributes' do
      candle = build(:candle_series_record, instrument: instrument)
      expect(candle).to be_valid
    end

    it 'requires instrument' do
      candle = build(:candle_series_record, instrument: nil)
      expect(candle).not_to be_valid
    end

    it 'requires timeframe' do
      candle = build(:candle_series_record, instrument: instrument, timeframe: nil)
      expect(candle).not_to be_valid
    end

    it 'requires timestamp' do
      candle = build(:candle_series_record, instrument: instrument, timestamp: nil)
      expect(candle).not_to be_valid
    end

    it 'has unique timestamp per instrument and timeframe' do
      # Use normalized timestamp (beginning of day) to match database constraint
      normalized_timestamp = 1.day.ago.beginning_of_day
      create(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: normalized_timestamp)

      duplicate = build(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: normalized_timestamp)
      expect(duplicate).not_to be_valid
    end
  end

  describe '#to_candle' do
    it 'converts to candle' do
      record = create(:candle_series_record, instrument: instrument)
      candle = record.to_candle

      expect(candle.timestamp).to eq(record.timestamp)
      expect(candle.close).to eq(record.close.to_f)
    end
  end

  describe '.latest_for' do
    it 'finds latest for instrument and timeframe' do
      create(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: 3.days.ago)
      latest = create(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: 1.day.ago)

      found = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: '1D')
      expect(found.id).to eq(latest.id)
    end
  end

  describe 'scopes' do
    it 'filters by instrument' do
      instrument1 = create(:instrument)
      instrument2 = create(:instrument)
      candle1 = create(:candle_series_record, instrument: instrument1, timeframe: '1D')
      candle2 = create(:candle_series_record, instrument: instrument2, timeframe: '1D')

      filtered = CandleSeriesRecord.for_instrument(instrument1)
      expect(filtered).to include(candle1)
      expect(filtered).not_to include(candle2)
    end

    it 'filters by timeframe' do
      candle1 = create(:candle_series_record, instrument: instrument, timeframe: '1D')
      candle2 = create(:candle_series_record, instrument: instrument, timeframe: '1W')

      filtered = CandleSeriesRecord.for_timeframe('1D')
      expect(filtered).to include(candle1)
      expect(filtered).not_to include(candle2)
    end

    it 'orders by timestamp ascending' do
      candle1 = create(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: 3.days.ago)
      candle2 = create(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: 2.days.ago)
      candle3 = create(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: 1.day.ago)

      ordered = CandleSeriesRecord.ordered
      expect(ordered.to_a).to eq([candle1, candle2, candle3])
    end

    it 'filters by date range' do
      from_date = 5.days.ago.to_date
      to_date = 2.days.ago.to_date

      candle1 = create(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: 4.days.ago)
      candle2 = create(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: 1.day.ago)
      candle3 = create(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: 10.days.ago)

      filtered = CandleSeriesRecord.between_dates(from_date, to_date)
      expect(filtered).to include(candle1)
      expect(filtered).not_to include(candle2)
      expect(filtered).not_to include(candle3)
    end

    it 'handles recent scope with limit' do
      create_list(:candle_series_record, 5, instrument: instrument, timeframe: '1D',
        timestamp: (4.days.ago..Time.current).step(1.day).to_a)

      recent = CandleSeriesRecord.recent(3)
      expect(recent.count).to eq(3)
    end
  end

  describe 'validations' do
    it 'requires open, high, low, close to be numeric' do
      candle = build(:candle_series_record, instrument: instrument, open: 'invalid')
      expect(candle).not_to be_valid
    end

    it 'requires volume to be integer' do
      candle = build(:candle_series_record, instrument: instrument, volume: 'invalid')
      expect(candle).not_to be_valid
    end

    it 'requires volume to be >= 0' do
      candle = build(:candle_series_record, instrument: instrument, volume: -1)
      expect(candle).not_to be_valid
    end

    it 'allows volume to be 0' do
      candle = build(:candle_series_record, instrument: instrument, volume: 0)
      expect(candle).to be_valid
    end
  end

  describe 'edge cases' do
    it 'handles to_candle with decimal values' do
      record = create(:candle_series_record,
        instrument: instrument,
        open: 100.5,
        high: 105.5,
        low: 99.5,
        close: 103.5,
        volume: 1_000_000)
      candle = record.to_candle

      expect(candle.open).to eq(100.5)
      expect(candle.high).to eq(105.5)
      expect(candle.low).to eq(99.5)
      expect(candle.close).to eq(103.5)
      expect(candle.volume).to eq(1_000_000)
    end

    it 'handles latest_for with no candles' do
      found = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: '1D')
      expect(found).to be_nil
    end

    it 'handles latest_for with different timeframe' do
      create(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: 1.day.ago)
      create(:candle_series_record, instrument: instrument, timeframe: '1W', timestamp: 1.week.ago)

      found = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: '1W')
      expect(found.timeframe).to eq('1W')
    end
  end
end

