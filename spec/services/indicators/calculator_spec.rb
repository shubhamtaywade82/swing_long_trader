# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::Calculator, type: :service do
  let(:series) { CandleSeries.new(symbol: 'TEST', interval: '1D') }

  before do
    50.times { series.add_candle(create(:candle)) }
  end

  describe '#rsi' do
    it 'delegates to series.rsi' do
      allow(series).to receive(:rsi).and_return(65.0)

      calculator = described_class.new(series)
      result = calculator.rsi(14)

      expect(result).to eq(65.0)
      expect(series).to have_received(:rsi).with(14)
    end

    it 'uses default period of 14' do
      allow(series).to receive(:rsi).and_return(65.0)

      calculator = described_class.new(series)
      calculator.rsi

      expect(series).to have_received(:rsi).with(14)
    end
  end

  describe '#macd' do
    it 'delegates to series.macd' do
      allow(series).to receive(:macd).and_return({ macd: 1.0, signal: 0.5, histogram: 0.5 })

      calculator = described_class.new(series)
      result = calculator.macd(12, 26, 9)

      expect(result).to be_present
      expect(series).to have_received(:macd).with(12, 26, 9)
    end
  end

  describe '#adx' do
    it 'delegates to series.adx' do
      allow(series).to receive(:adx).and_return(25.0)

      calculator = described_class.new(series)
      result = calculator.adx(14)

      expect(result).to eq(25.0)
      expect(series).to have_received(:adx).with(14)
    end
  end

  describe '#bullish_signal?' do
    context 'when conditions are met' do
      before do
        allow(series).to receive(:rsi).and_return(25.0)
        allow(series).to receive(:adx).and_return(25.0)
        allow(series).to receive(:closes).and_return([100.0, 105.0, 110.0])
      end

      it 'returns true' do
        calculator = described_class.new(series)

        expect(calculator.bullish_signal?).to be true
      end
    end

    context 'when conditions are not met' do
      before do
        allow(series).to receive(:rsi).and_return(50.0)
        allow(series).to receive(:adx).and_return(15.0)
        allow(series).to receive(:closes).and_return([100.0, 95.0, 90.0])
      end

      it 'returns false' do
        calculator = described_class.new(series)

        expect(calculator.bullish_signal?).to be false
      end
    end
  end

  describe '#bearish_signal?' do
    context 'when conditions are met' do
      before do
        allow(series).to receive(:rsi).and_return(75.0)
        allow(series).to receive(:adx).and_return(25.0)
        allow(series).to receive(:closes).and_return([110.0, 105.0, 100.0])
      end

      it 'returns true' do
        calculator = described_class.new(series)

        expect(calculator.bearish_signal?).to be true
      end
    end

    context 'when conditions are not met' do
      before do
        allow(series).to receive(:rsi).and_return(50.0)
        allow(series).to receive(:adx).and_return(15.0)
        allow(series).to receive(:closes).and_return([100.0, 105.0, 110.0])
      end

      it 'returns false' do
        calculator = described_class.new(series)

        expect(calculator.bearish_signal?).to be false
      end
    end
  end
end

