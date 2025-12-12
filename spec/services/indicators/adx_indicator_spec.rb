# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::AdxIndicator, type: :service do
  let(:series) { CandleSeries.new(symbol: 'TEST', interval: '1D') }

  before do
    50.times { series.add_candle(create(:candle)) }
  end

  describe '#initialize' do
    it 'initializes with default period' do
      indicator = described_class.new(series: series)

      expect(indicator.min_required_candles).to eq(15) # period + 1
    end

    it 'uses custom period from config' do
      indicator = described_class.new(series: series, config: { period: 20 })

      expect(indicator.min_required_candles).to eq(21)
    end
  end

  describe '#ready?' do
    it 'returns false when index is too small' do
      indicator = described_class.new(series: series)

      expect(indicator.ready?(10)).to be false
    end

    it 'returns true when index is sufficient' do
      indicator = described_class.new(series: series)

      expect(indicator.ready?(15)).to be true
    end
  end

  describe '#calculate_at' do
    context 'when ADX value is above minimum strength' do
      before do
        allow_any_instance_of(CandleSeries).to receive(:adx).and_return(25.0)
      end

      it 'returns ADX value with direction and confidence' do
        indicator = described_class.new(series: series)
        result = indicator.calculate_at(20)

        expect(result).to be_present
        expect(result[:value]).to eq(25.0)
        expect(result).to have_key(:direction)
        expect(result).to have_key(:confidence)
      end
    end

    context 'when ADX value is below minimum strength' do
      before do
        allow_any_instance_of(CandleSeries).to receive(:adx).and_return(15.0)
      end

      it 'returns nil' do
        indicator = described_class.new(series: series, config: { min_strength: 20 })
        result = indicator.calculate_at(20)

        expect(result).to be_nil
      end
    end

    context 'when index is not ready' do
      it 'returns nil' do
        indicator = described_class.new(series: series)
        result = indicator.calculate_at(10)

        expect(result).to be_nil
      end
    end
  end
end

