# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::HolyGrail, type: :service do
  let(:candles) { create_list(:candle, 150) }

  describe '.demo_config' do
    it 'returns demo configuration' do
      config = described_class.demo_config

      expect(config[:adx_gate]).to eq(0.0)
      expect(config[:rsi_up_min]).to eq(0.0)
      expect(config[:rsi_down_max]).to eq(100.0)
    end
  end

  describe '#initialize' do
    context 'when candles are sufficient' do
      it 'initializes successfully' do
        indicator = described_class.new(candles: candles)

        expect(indicator).to be_present
      end
    end

    context 'when candles are insufficient' do
      it 'raises ArgumentError' do
        expect do
          described_class.new(candles: candles.first(50))
        end.to raise_error(ArgumentError, /need ≥/)
      end
    end
  end

  describe '#call' do
    before do
      allow_any_instance_of(described_class).to receive(:sma).and_return(100.0)
      allow_any_instance_of(described_class).to receive(:ema).and_return(95.0)
      allow_any_instance_of(described_class).to receive(:rsi).and_return(50.0)
      allow_any_instance_of(described_class).to receive(:adx).and_return(25.0)
      allow_any_instance_of(described_class).to receive(:atr).and_return(5.0)
      allow_any_instance_of(described_class).to receive(:macd_hash).and_return({ macd: 1.0, signal: 0.5, histogram: 0.5 })
    end

    it 'calculates Holy Grail indicators' do
      indicator = described_class.new(candles: candles)
      result = indicator.call

      expect(result).to be_present
      expect(result).to respond_to(:bias)
      expect(result).to respond_to(:adx)
      expect(result).to respond_to(:momentum)
      expect(result).to respond_to(:proceed?)
    end

    it 'returns result as hash' do
      indicator = described_class.new(candles: candles)
      result = indicator.call

      expect(result.to_h).to be_a(Hash)
    end

    it 'handles bullish bias' do
      allow_any_instance_of(described_class).to receive(:sma).and_return(105.0)
      allow_any_instance_of(described_class).to receive(:ema).and_return(95.0)
      allow_any_instance_of(described_class).to receive(:rsi).and_return(60.0)
      allow_any_instance_of(described_class).to receive(:adx).and_return(25.0)
      allow_any_instance_of(described_class).to receive(:macd_hash).and_return({ macd: 1.0, signal: 0.5 })

      indicator = described_class.new(candles: candles)
      result = indicator.call

      expect(result.bias).to eq(:bullish)
    end

    it 'handles bearish bias' do
      allow_any_instance_of(described_class).to receive(:sma).and_return(95.0)
      allow_any_instance_of(described_class).to receive(:ema).and_return(105.0)
      allow_any_instance_of(described_class).to receive(:rsi).and_return(40.0)
      allow_any_instance_of(described_class).to receive(:adx).and_return(25.0)
      allow_any_instance_of(described_class).to receive(:macd_hash).and_return({ macd: 0.5, signal: 1.0 })

      indicator = described_class.new(candles: candles)
      result = indicator.call

      expect(result.bias).to eq(:bearish)
    end

    it 'handles neutral bias' do
      allow_any_instance_of(described_class).to receive(:sma).and_return(100.0)
      allow_any_instance_of(described_class).to receive(:ema).and_return(100.0)

      indicator = described_class.new(candles: candles)
      result = indicator.call

      expect(result.bias).to eq(:neutral)
    end

    it 'handles different momentum values' do
      allow_any_instance_of(described_class).to receive(:sma).and_return(100.0)
      allow_any_instance_of(described_class).to receive(:ema).and_return(95.0)
      allow_any_instance_of(described_class).to receive(:rsi).and_return(50.0)
      allow_any_instance_of(described_class).to receive(:macd_hash).and_return({ macd: 0.5, signal: 1.0 })

      indicator = described_class.new(candles: candles)
      result = indicator.call

      expect(result.momentum).to eq(:flat)
    end

    it 'handles proceed? logic for bullish' do
      allow_any_instance_of(described_class).to receive(:sma).and_return(105.0)
      allow_any_instance_of(described_class).to receive(:ema).and_return(95.0)
      allow_any_instance_of(described_class).to receive(:rsi).and_return(60.0)
      allow_any_instance_of(described_class).to receive(:adx).and_return(25.0)
      allow_any_instance_of(described_class).to receive(:macd_hash).and_return({ macd: 1.0, signal: 0.5 })

      indicator = described_class.new(candles: candles)
      result = indicator.call

      expect(result.proceed?).to be true
    end

    it 'handles proceed? logic for bearish' do
      allow_any_instance_of(described_class).to receive(:sma).and_return(95.0)
      allow_any_instance_of(described_class).to receive(:ema).and_return(105.0)
      allow_any_instance_of(described_class).to receive(:rsi).and_return(40.0)
      allow_any_instance_of(described_class).to receive(:adx).and_return(25.0)
      allow_any_instance_of(described_class).to receive(:macd_hash).and_return({ macd: 0.5, signal: 1.0 })

      indicator = described_class.new(candles: candles)
      result = indicator.call

      expect(result.proceed?).to be true
    end

    it 'handles proceed? logic for neutral' do
      allow_any_instance_of(described_class).to receive(:sma).and_return(100.0)
      allow_any_instance_of(described_class).to receive(:ema).and_return(100.0)

      indicator = described_class.new(candles: candles)
      result = indicator.call

      expect(result.proceed?).to be false
    end

    it 'handles custom config' do
      config = { adx_gate: 30.0, rsi_up_min: 50.0 }
      indicator = described_class.new(candles: candles, config: config)

      expect(indicator).to be_present
    end
  end

  describe '#analyze_volatility' do
    before do
      allow_any_instance_of(described_class).to receive(:atr).and_return(5.0)
    end

    it 'analyzes volatility' do
      indicator = described_class.new(candles: candles)
      result = indicator.analyze_volatility

      expect(result).to have_key(:level)
      expect(result).to have_key(:atr_value)
      expect(result).to have_key(:volatility_percentile)
    end

    it 'handles insufficient data gracefully' do
      allow_any_instance_of(described_class).to receive(:atr).and_raise(StandardError, 'Not enough data')

      indicator = described_class.new(candles: candles)
      result = indicator.analyze_volatility

      expect(result[:volatility_percentile]).to eq(0.5)
    end
  end

  describe 'private methods' do
    let(:indicator) { described_class.new(candles: candles) }

    describe '#closes' do
      it 'extracts close prices from candles' do
        closes = indicator.send(:closes)
        expect(closes).to be_an(Array)
        expect(closes.size).to eq(candles.size)
      end
    end

    describe '#sma' do
      it 'calculates simple moving average' do
        sma_value = indicator.send(:sma, 20)
        expect(sma_value).to be_a(Numeric)
      end
    end

    describe '#ema' do
      it 'calculates exponential moving average' do
        ema_value = indicator.send(:ema, 20)
        expect(ema_value).to be_a(Numeric)
      end
    end

    describe '#rsi' do
      it 'calculates RSI' do
        rsi_value = indicator.send(:rsi, 14)
        expect(rsi_value).to be_a(Numeric)
        expect(rsi_value).to be_between(0, 100)
      end
    end

    describe '#adx' do
      it 'calculates ADX' do
        adx_value = indicator.send(:adx, 14)
        expect(adx_value).to be_a(Numeric)
        expect(adx_value).to be >= 0
      end
    end

    describe '#atr' do
      it 'calculates ATR' do
        atr_value = indicator.send(:atr, 20)
        expect(atr_value).to be_a(Numeric)
        expect(atr_value).to be >= 0
      end
    end

    describe '#macd_hash' do
      it 'calculates MACD and returns hash' do
        macd_result = indicator.send(:macd_hash)
        expect(macd_result).to be_a(Hash)
        expect(macd_result).to have_key(:macd)
        expect(macd_result).to have_key(:signal)
        expect(macd_result).to have_key(:histogram)
      end
    end
  end

  describe 'edge cases' do
    it 'handles proceed? when ADX is below gate' do
      allow_any_instance_of(described_class).to receive(:sma).and_return(105.0)
      allow_any_instance_of(described_class).to receive(:ema).and_return(95.0)
      allow_any_instance_of(described_class).to receive(:rsi).and_return(60.0)
      allow_any_instance_of(described_class).to receive(:adx).and_return(15.0) # Below gate (20.0)
      allow_any_instance_of(described_class).to receive(:macd_hash).and_return({ macd: 1.0, signal: 0.5 })

      indicator = described_class.new(candles: candles)
      result = indicator.call

      expect(result.proceed?).to be false
    end

    it 'handles proceed? when RSI conditions not met for bullish' do
      allow_any_instance_of(described_class).to receive(:sma).and_return(105.0)
      allow_any_instance_of(described_class).to receive(:ema).and_return(95.0)
      allow_any_instance_of(described_class).to receive(:rsi).and_return(30.0) # Below rsi_up_min (40.0)
      allow_any_instance_of(described_class).to receive(:adx).and_return(25.0)
      allow_any_instance_of(described_class).to receive(:macd_hash).and_return({ macd: 1.0, signal: 0.5 })

      indicator = described_class.new(candles: candles)
      result = indicator.call

      expect(result.proceed?).to be false
    end

    it 'handles proceed? when RSI conditions not met for bearish' do
      allow_any_instance_of(described_class).to receive(:sma).and_return(95.0)
      allow_any_instance_of(described_class).to receive(:ema).and_return(105.0)
      allow_any_instance_of(described_class).to receive(:rsi).and_return(70.0) # Above rsi_down_max (60.0)
      allow_any_instance_of(described_class).to receive(:adx).and_return(25.0)
      allow_any_instance_of(described_class).to receive(:macd_hash).and_return({ macd: 0.5, signal: 1.0 })

      indicator = described_class.new(candles: candles)
      result = indicator.call

      expect(result.proceed?).to be false
    end

    it 'handles custom min_candles config' do
      config = { min_candles: 50 }
      indicator = described_class.new(candles: candles.first(60), config: config)

      expect(indicator).to be_present
    end

    it 'raises error when custom min_candles not met' do
      config = { min_candles: 200 }
      expect do
        described_class.new(candles: candles, config: config)
      end.to raise_error(ArgumentError, /need ≥ 200/)
    end
  end
end

