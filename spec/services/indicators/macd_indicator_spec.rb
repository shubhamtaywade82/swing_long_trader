# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::MacdIndicator, type: :service do
  let(:series) { CandleSeries.new(symbol: 'TEST', interval: '1D') }

  before do
    50.times { series.add_candle(create(:candle)) }
  end

  describe '#initialize' do
    it 'initializes with default periods' do
      indicator = described_class.new(series: series)

      expect(indicator.min_required_candles).to eq(35) # slow_period + signal_period
    end

    it 'uses custom periods from config' do
      indicator = described_class.new(series: series, config: { fast_period: 10, slow_period: 20, signal_period: 5 })

      expect(indicator.min_required_candles).to eq(25)
    end
  end

  describe '#ready?' do
    it 'returns false when index is too small' do
      indicator = described_class.new(series: series)

      expect(indicator.ready?(30)).to be false
    end

    it 'returns true when index is sufficient' do
      indicator = described_class.new(series: series)

      expect(indicator.ready?(35)).to be true
    end
  end

  describe '#calculate_at' do
    context 'when MACD is bullish' do
      before do
        allow_any_instance_of(CandleSeries).to receive(:macd).and_return([1.0, 0.5, 0.5])
      end

      it 'returns bullish signal' do
        indicator = described_class.new(series: series)
        result = indicator.calculate_at(40)

        expect(result).to be_present
        expect(result[:direction]).to eq(:bullish)
        expect(result[:value]).to have_key(:macd)
        expect(result[:value]).to have_key(:signal)
        expect(result[:value]).to have_key(:histogram)
      end
    end

    context 'when MACD is bearish' do
      before do
        allow_any_instance_of(CandleSeries).to receive(:macd).and_return([0.5, 1.0, -0.5])
      end

      it 'returns bearish signal' do
        indicator = described_class.new(series: series)
        result = indicator.calculate_at(40)

        expect(result).to be_present
        expect(result[:direction]).to eq(:bearish)
      end
    end

    context 'when MACD result is invalid' do
      before do
        allow_any_instance_of(CandleSeries).to receive(:macd).and_return(nil)
      end

      it 'returns nil' do
        indicator = described_class.new(series: series)
        result = indicator.calculate_at(40)

        expect(result).to be_nil
      end
    end
  end
end

