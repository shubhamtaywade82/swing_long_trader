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
      create(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: 1.day.ago)

      duplicate = build(:candle_series_record, instrument: instrument, timeframe: '1D', timestamp: 1.day.ago)
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
end

