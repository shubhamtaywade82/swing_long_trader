# frozen_string_literal: true

require 'test_helper'

class CandleSeriesRecordTest < ActiveSupport::TestCase
  setup do
    @instrument = create(:instrument)
  end

  test 'should be valid with valid attributes' do
    candle = build(:candle_series_record, instrument: @instrument)
    assert candle.valid?
  end

  test 'should require instrument' do
    candle = build(:candle_series_record, instrument: nil)
    assert_not candle.valid?
  end

  test 'should require timeframe' do
    candle = build(:candle_series_record, instrument: @instrument, timeframe: nil)
    assert_not candle.valid?
  end

  test 'should require timestamp' do
    candle = build(:candle_series_record, instrument: @instrument, timestamp: nil)
    assert_not candle.valid?
  end

  test 'should have unique timestamp per instrument and timeframe' do
    create(:candle_series_record, instrument: @instrument, timeframe: '1D', timestamp: 1.day.ago)

    duplicate = build(:candle_series_record, instrument: @instrument, timeframe: '1D', timestamp: 1.day.ago)
    assert_not duplicate.valid?
  end

  test 'should convert to candle' do
    record = create(:candle_series_record, instrument: @instrument)
    candle = record.to_candle

    assert_equal record.timestamp, candle.timestamp
    assert_equal record.close.to_f, candle.close
  end

  test 'should find latest for instrument and timeframe' do
    create(:candle_series_record, instrument: @instrument, timeframe: '1D', timestamp: 3.days.ago)
    latest = create(:candle_series_record, instrument: @instrument, timeframe: '1D', timestamp: 1.day.ago)

    found = CandleSeriesRecord.latest_for(instrument: @instrument, timeframe: '1D')
    assert_equal latest.id, found.id
  end
end


