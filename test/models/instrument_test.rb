# frozen_string_literal: true

require 'test_helper'

class InstrumentTest < ActiveSupport::TestCase
  test 'should be valid with valid attributes' do
    instrument = build(:instrument)
    assert instrument.valid?
  end

  test 'should require security_id' do
    instrument = build(:instrument, security_id: nil)
    assert_not instrument.valid?
  end

  test 'should require symbol_name' do
    instrument = build(:instrument, symbol_name: nil)
    assert_not instrument.valid?
  end

  test 'should have unique security_id' do
    create(:instrument, security_id: 'SEC123')
    instrument = build(:instrument, security_id: 'SEC123')
    assert_not instrument.valid?
  end

  test 'should have many candle_series_records' do
    instrument = create(:instrument)
    create_list(:candle_series_record, 3, instrument: instrument)
    assert_equal 3, instrument.candle_series_records.count
  end

  test 'should load daily candles' do
    instrument = create(:instrument)
    create_list(:daily_candle, 5, instrument: instrument)

    series = instrument.load_daily_candles(limit: 10)
    assert_not_nil series
    assert_equal 5, series.candles.size
  end

  test 'should check if has candles' do
    instrument = create(:instrument)
    assert_not instrument.has_candles?(timeframe: '1D')

    create(:daily_candle, instrument: instrument)
    assert instrument.has_candles?(timeframe: '1D')
  end
end


