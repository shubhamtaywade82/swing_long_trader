# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::RsiIndicator, type: :service do
  let(:series) { CandleSeries.new(symbol: 'TEST', interval: '1D') }

  before do
    50.times { series.add_candle(create(:candle)) }
  end

  describe '#initialize' do
    it 'initializes with default period' do
      indicator = described_class.new(series: series)

      expect(indicator.min_required_candles).to eq(15) # period + 1
    end

    it 'uses custom oversold/overbought levels' do
      indicator = described_class.new(series: series, config: { oversold: 25, overbought: 75 })

      expect(indicator).to be_present
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
    context 'when RSI is oversold' do
      before do
        allow_any_instance_of(CandleSeries).to receive(:rsi).and_return(25.0)
      end

      it 'returns bullish signal' do
        indicator = described_class.new(series: series)
        result = indicator.calculate_at(20)

        expect(result).to be_present
        expect(result[:direction]).to eq(:bullish)
        expect(result[:value]).to eq(25.0)
      end
    end

    context 'when RSI is overbought' do
      before do
        allow_any_instance_of(CandleSeries).to receive(:rsi).and_return(75.0)
      end

      it 'returns bearish signal' do
        indicator = described_class.new(series: series)
        result = indicator.calculate_at(20)

        expect(result).to be_present
        expect(result[:direction]).to eq(:bearish)
        expect(result[:value]).to eq(75.0)
      end
    end

    context 'when RSI is neutral' do
      before do
        allow_any_instance_of(CandleSeries).to receive(:rsi).and_return(50.0)
      end

      it 'returns nil' do
        indicator = described_class.new(series: series)
        result = indicator.calculate_at(20)

        expect(result).to be_nil
      end
    end
  end
end

