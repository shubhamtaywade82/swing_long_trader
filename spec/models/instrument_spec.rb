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

  describe 'scopes' do
    it 'filters enabled instruments' do
      enabled = create(:instrument, enabled: true)
      disabled = create(:instrument, enabled: false)

      expect(Instrument.enabled).to include(enabled)
      expect(Instrument.enabled).not_to include(disabled)
    end
  end

  describe 'validations' do
    it 'requires exchange' do
      instrument = build(:instrument, exchange: nil)
      expect(instrument).not_to be_valid
    end

    it 'requires segment' do
      instrument = build(:instrument, segment: nil)
      expect(instrument).not_to be_valid
    end

    it 'requires exchange_segment when exchange and segment are missing' do
      instrument = build(:instrument, exchange: nil, segment: nil, exchange_segment: nil)
      expect(instrument).not_to be_valid
    end

    it 'allows exchange_segment when exchange and segment are present' do
      instrument = build(:instrument, exchange: 'NSE', segment: 'E', exchange_segment: 'NSE_E')
      expect(instrument).to be_valid
    end
  end

  describe 'edge cases' do
    it 'handles instrument with nil lot_size' do
      instrument = create(:instrument, lot_size: nil)
      expect(instrument).to be_valid
    end

    it 'handles instrument with zero lot_size' do
      instrument = create(:instrument, lot_size: 0)
      expect(instrument).to be_valid
    end

    it 'handles instrument with nil expiry_date' do
      instrument = create(:instrument, expiry_date: nil)
      expect(instrument).to be_valid
    end

    it 'handles instrument with nil strike_price' do
      instrument = create(:instrument, strike_price: nil)
      expect(instrument).to be_valid
    end

    it 'handles instrument with nil option_type' do
      instrument = create(:instrument, option_type: nil)
      expect(instrument).to be_valid
    end

    it 'handles load_daily_candles with no candles' do
      series = instrument.load_daily_candles(limit: 10)
      expect(series).to be_nil
    end

    it 'handles load_weekly_candles with no candles' do
      series = instrument.load_weekly_candles(limit: 52)
      expect(series).to be_nil
    end

    it 'handles has_candles? with different timeframes' do
      create(:candle_series_record, instrument: instrument, timeframe: '1D')
      create(:candle_series_record, instrument: instrument, timeframe: '1W')

      expect(instrument.has_candles?(timeframe: '1D')).to be true
      expect(instrument.has_candles?(timeframe: '1W')).to be true
      expect(instrument.has_candles?(timeframe: '1H')).to be false
    end

    it 'handles has_candles? with nil timeframe' do
      expect(instrument.has_candles?(timeframe: nil)).to be false
    end
  end

  describe 'class methods' do
    describe '.segment_key_for' do
      it 'returns correct segment for known codes' do
        expect(Instrument.segment_key_for('E')).to eq('equity')
        expect(Instrument.segment_key_for('I')).to eq('index')
        expect(Instrument.segment_key_for('D')).to eq('derivatives')
      end

      it 'handles unknown segment codes' do
        expect(Instrument.segment_key_for('UNKNOWN')).to be_nil
      end

      it 'handles nil segment code' do
        expect(Instrument.segment_key_for(nil)).to be_nil
      end
    end
  end
end

