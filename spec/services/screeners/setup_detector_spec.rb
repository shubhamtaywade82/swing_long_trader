# frozen_string_literal: true

require "rails_helper"

RSpec.describe Screeners::SetupDetector do
  let(:instrument) { create(:instrument, symbol_name: "RELIANCE") }
  let(:candles) { Array.new(100) { |i| build(:candle, timestamp: i.days.ago, close: 2500.0 + i) } }
  let(:daily_series) { instance_double(CandleSeries, candles: candles, latest_close: 2500.0) }
  let(:indicators) do
    {
      latest_close: 2500.0,
      ema20: 2480.0,
      ema50: 2450.0,
      ema200: 2400.0,
      atr: 25.0,
      adx: 30.0,
      rsi: 55.0, # RSI recovering above 45-50
      supertrend: { direction: :bullish },
      macd: [1.0, 0.5, 0.3], # MACD bullish
    }
  end
  let(:candidate) { { instrument_id: instrument.id, symbol: "RELIANCE" } }

  describe ".call" do
    context "when RSI is recovering above 45-50" do
      it "allows setup when RSI is between 45-70 and price is rising" do
        indicators[:rsi] = 52.0
        allow(daily_series).to receive(:candles).and_return(candles)
        # Mock recent candles with rising price
        recent_candles = [
          build(:candle, timestamp: 4.days.ago, close: 2480.0),
          build(:candle, timestamp: 3.days.ago, close: 2490.0),
          build(:candle, timestamp: 2.days.ago, close: 2495.0),
          build(:candle, timestamp: 1.day.ago, close: 2500.0),
          build(:candle, timestamp: Time.current, close: 2505.0),
        ]
        allow(daily_series).to receive(:candles).and_return(recent_candles + candles[5..])

        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
        )

        expect(result[:status]).not_to eq(Screeners::SetupDetector::NOT_READY)
      end

      it "waits when RSI is below 45" do
        indicators[:rsi] = 40.0

        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
        )

        expect(result[:status]).to eq(Screeners::SetupDetector::WAIT_PULLBACK)
        expect(result[:reason]).to include("below 45")
      end

      it "waits when RSI is above 70 (overbought)" do
        indicators[:rsi] = 75.0

        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
        )

        expect(result[:status]).to eq(Screeners::SetupDetector::WAIT_PULLBACK)
        expect(result[:reason]).to include("Overbought")
      end
    end

    context "when trend is bullish" do
      it "returns READY when all conditions are met" do
        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
        )

        expect(result[:status]).to eq(Screeners::SetupDetector::READY)
      end
    end
  end
end
