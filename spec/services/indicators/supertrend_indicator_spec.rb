# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::SupertrendIndicator, type: :service do
  let(:series) { CandleSeries.new(symbol: 'TEST', interval: '1D') }

  before do
    50.times { series.add_candle(create(:candle)) }
  end

  describe '#initialize' do
    it 'initializes with default period' do
      indicator = described_class.new(series: series)

      expect(indicator.min_required_candles).to eq(7)
    end

    it 'uses custom period from config' do
      indicator = described_class.new(series: series, config: { period: 10 })

      expect(indicator.min_required_candles).to eq(10)
    end
  end

  describe '#ready?' do
    it 'returns false when index is too small' do
      indicator = described_class.new(series: series)

      expect(indicator.ready?(5)).to be false
    end

    it 'returns true when index is sufficient' do
      indicator = described_class.new(series: series)

      expect(indicator.ready?(7)).to be true
    end
  end

  describe '#calculate_at' do
    context 'when supertrend is calculated' do
      before do
        allow(Indicators::Supertrend).to receive(:new).and_return(
          double(call: {
            trend: :bullish,
            line: Array.new(50, 100.0)
          })
        )
      end

      it 'returns supertrend value with direction' do
        indicator = described_class.new(series: series)
        result = indicator.calculate_at(20)

        expect(result).to be_present
        expect(result).to have_key(:value)
        expect(result).to have_key(:direction)
        expect(result).to have_key(:confidence)
      end
    end

    context 'when supertrend calculation fails' do
      before do
        allow(Indicators::Supertrend).to receive(:new).and_return(
          double(call: nil)
        )
      end

      it 'returns nil' do
        indicator = described_class.new(series: series)
        result = indicator.calculate_at(20)

        expect(result).to be_nil
      end
    end
  end
end

