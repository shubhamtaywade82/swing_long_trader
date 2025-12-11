# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Swing::SignalBuilder do
  let(:instrument) { create(:instrument, symbol_name: 'TEST') }
  let(:series) { create(:candle_series, symbol: 'TEST', interval: '1D') }
  let(:indicators) do
    {
      ema20: 100.0,
      ema50: 95.0,
      rsi: 60.0,
      adx: 25.0,
      atr: 5.0,
      supertrend: { trend: :bullish, value: 98.0 }
    }
  end

  describe '.call' do
    context 'with bullish trend' do
      it 'returns a signal hash' do
        result = described_class.call(
          instrument: instrument,
          series: series,
          indicators: indicators,
          direction: :long
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key(:symbol)
        expect(result).to have_key(:direction)
        expect(result).to have_key(:entry_price)
      end

      it 'sets direction to long for bullish signals' do
        result = described_class.call(
          instrument: instrument,
          series: series,
          indicators: indicators,
          direction: :long
        )

        expect(result[:direction]).to eq(:long)
      end

      it 'calculates entry price from latest close' do
        allow(series).to receive_message_chain(:candles, :last, :close).and_return(100.0)

        result = described_class.call(
          instrument: instrument,
          series: series,
          indicators: indicators,
          direction: :long
        )

        expect(result[:entry_price]).to eq(100.0)
      end

      it 'calculates stop loss based on ATR' do
        allow(series).to receive_message_chain(:candles, :last, :close).and_return(100.0)
        indicators[:atr] = 5.0

        result = described_class.call(
          instrument: instrument,
          series: series,
          indicators: indicators,
          direction: :long
        )

        expect(result[:stop_loss]).to be < result[:entry_price]
        expect(result[:stop_loss]).to be_a(Numeric)
      end

      it 'calculates take profit based on risk-reward ratio' do
        allow(series).to receive_message_chain(:candles, :last, :close).and_return(100.0)

        result = described_class.call(
          instrument: instrument,
          series: series,
          indicators: indicators,
          direction: :long,
          risk_reward_ratio: 2.0
        )

        expect(result[:take_profit]).to be > result[:entry_price]
        risk = result[:entry_price] - result[:stop_loss]
        reward = result[:take_profit] - result[:entry_price]
        expect(reward / risk).to be >= 2.0
      end

      it 'calculates position size' do
        allow(series).to receive_message_chain(:candles, :last, :close).and_return(100.0)

        result = described_class.call(
          instrument: instrument,
          series: series,
          indicators: indicators,
          direction: :long,
          capital: 100_000,
          risk_per_trade: 2.0
        )

        expect(result[:quantity]).to be_a(Integer)
        expect(result[:quantity]).to be > 0
      end

      it 'calculates confidence score' do
        result = described_class.call(
          instrument: instrument,
          series: series,
          indicators: indicators,
          direction: :long
        )

        expect(result[:confidence]).to be_a(Numeric)
        expect(result[:confidence]).to be_between(0, 100)
      end
    end

    context 'with bearish trend' do
      let(:bearish_indicators) do
        indicators.merge(
          ema20: 95.0,
          ema50: 100.0,
          supertrend: { trend: :bearish, value: 102.0 }
        )
      end

      it 'sets direction to short for bearish signals' do
        result = described_class.call(
          instrument: instrument,
          series: series,
          indicators: bearish_indicators,
          direction: :short
        )

        expect(result[:direction]).to eq(:short)
      end

      it 'calculates stop loss above entry for short positions' do
        allow(series).to receive_message_chain(:candles, :last, :close).and_return(100.0)

        result = described_class.call(
          instrument: instrument,
          series: series,
          indicators: bearish_indicators,
          direction: :short
        )

        expect(result[:stop_loss]).to be > result[:entry_price]
      end

      it 'calculates take profit below entry for short positions' do
        allow(series).to receive_message_chain(:candles, :last, :close).and_return(100.0)

        result = described_class.call(
          instrument: instrument,
          series: series,
          indicators: bearish_indicators,
          direction: :short,
          risk_reward_ratio: 2.0
        )

        expect(result[:take_profit]).to be < result[:entry_price]
      end
    end

    context 'with missing indicators' do
      it 'handles missing ATR gracefully' do
        indicators_without_atr = indicators.merge(atr: nil)

        result = described_class.call(
          instrument: instrument,
          series: series,
          indicators: indicators_without_atr,
          direction: :long
        )

        expect(result).to be_a(Hash)
        expect(result[:stop_loss]).to be_a(Numeric)
      end
    end
  end
end

