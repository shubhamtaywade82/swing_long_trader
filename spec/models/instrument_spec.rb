# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Instrument, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      instrument = build(:instrument)
      expect(instrument).to be_valid
    end

    it 'requires security_id' do
      instrument = build(:instrument, security_id: nil)
      expect(instrument).not_to be_valid
    end

    it 'requires symbol_name' do
      instrument = build(:instrument, symbol_name: nil)
      expect(instrument).not_to be_valid
    end

    it 'requires unique security_id within exchange and segment' do
      create(:instrument, security_id: 'SEC123', exchange: 'NSE', segment: 'E')
      # Same security_id, exchange, and segment should be invalid
      instrument = build(:instrument, security_id: 'SEC123', exchange: 'NSE', segment: 'E')
      expect(instrument).not_to be_valid

      # Same security_id but different exchange should be valid
      instrument2 = build(:instrument, security_id: 'SEC123', exchange: 'BSE', segment: 'E')
      expect(instrument2).to be_valid

      # Same security_id but different segment should be valid
      instrument3 = build(:instrument, security_id: 'SEC123', exchange: 'NSE', segment: 'I')
      expect(instrument3).to be_valid
    end
  end

  describe 'associations' do
    it 'has many candle_series_records' do
      instrument = create(:instrument)
      create_list(:candle_series_record, 3, instrument: instrument)
      expect(instrument.candle_series_records.count).to eq(3)
    end
  end

  describe 'methods' do
    let(:instrument) { create(:instrument) }

    it 'loads daily candles' do
      create_list(:daily_candle, 5, instrument: instrument)

      series = instrument.load_daily_candles(limit: 10)
      expect(series).not_to be_nil
      expect(series.candles.size).to eq(5)
    end

    it 'checks if has candles' do
      expect(instrument.has_candles?(timeframe: '1D')).to be false

      create(:daily_candle, instrument: instrument)
      expect(instrument.has_candles?(timeframe: '1D')).to be true
    end
  end
end

