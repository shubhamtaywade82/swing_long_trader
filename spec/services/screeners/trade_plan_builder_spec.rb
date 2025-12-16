# frozen_string_literal: true

require "rails_helper"

RSpec.describe Screeners::TradePlanBuilder do
  let(:instrument) { create(:instrument, symbol_name: "RELIANCE", ltp: 2500.0) }
  let(:daily_series) { instance_double(CandleSeries, candles: candles, latest_close: 2500.0) }
  let(:candles) { Array.new(100) { |i| build(:candle, timestamp: i.days.ago, close: 2500.0 + i) } }
  let(:indicators) do
    {
      latest_close: 2500.0,
      ema20: 2480.0,
      ema50: 2450.0,
      atr: 25.0, # 1% of price (low volatility)
    }
  end
  let(:setup_status) { { status: Screeners::SetupDetector::READY, reason: "Ready" } }
  let(:candidate) { { instrument_id: instrument.id, symbol: "RELIANCE" } }

  describe ".call" do
    context "when setup is READY" do
      it "generates trade plan with ATR-based stop loss and targets" do
        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
          setup_status: setup_status,
        )

        expect(result).not_to be_nil
        expect(result[:entry_price]).to be > 0
        expect(result[:stop_loss]).to be < result[:entry_price]
        expect(result[:tp1]).to be > result[:entry_price]
        expect(result[:tp2]).to be > result[:tp1]
        expect(result[:atr]).to eq(25.0)
        expect(result[:risk_reward]).to be >= 3.0
      end

      it "uses dynamic ATR multiplier for stop loss based on volatility" do
        # Low volatility: ATR % < 2%
        indicators[:atr] = 25.0 # 1% of 2500
        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
          setup_status: setup_status,
        )

        expect(result[:atr_sl_multiplier]).to eq(1.5) # Low volatility uses 1.5× ATR

        # Medium volatility: ATR % 2-5%
        indicators[:atr] = 75.0 # 3% of 2500
        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
          setup_status: setup_status,
        )

        expect(result[:atr_sl_multiplier]).to eq(2.0) # Medium volatility uses 2.0× ATR

        # High volatility: ATR % > 5%
        indicators[:atr] = 150.0 # 6% of 2500
        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
          setup_status: setup_status,
        )

        expect(result[:atr_sl_multiplier]).to eq(2.5) # High volatility uses 2.5× ATR
      end

      it "calculates TP1 as Entry + (ATR × 2)" do
        indicators[:atr] = 25.0
        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
          setup_status: setup_status,
        )

        expected_tp1 = result[:entry_price] + (25.0 * 2.0)
        expect(result[:tp1]).to be_within(0.01).of(expected_tp1)
      end

      it "calculates TP2 as Entry + (ATR × 4)" do
        indicators[:atr] = 25.0
        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
          setup_status: setup_status,
        )

        expected_tp2 = result[:entry_price] + (25.0 * 4.0)
        expect(result[:tp2]).to be_within(0.01).of(expected_tp2)
      end

      it "ensures minimum risk-reward ratio of 3R" do
        indicators[:atr] = 10.0 # Very small ATR
        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
          setup_status: setup_status,
        )

        expect(result[:risk_reward]).to be >= 3.0
      end

      it "rejects trade plan if risk-reward is below 3R" do
        # Create scenario where RR would be < 3R
        indicators[:atr] = 1.0 # Very small ATR
        indicators[:ema50] = 2495.0 # Very close to entry, tight stop

        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
          setup_status: setup_status,
        )

        # Should return nil if RR < 3.0
        expect(result).to be_nil
      end
    end

    context "when setup is not READY" do
      it "returns nil" do
        setup_status[:status] = Screeners::SetupDetector::WAIT_PULLBACK

        result = described_class.call(
          candidate: candidate,
          daily_series: daily_series,
          indicators: indicators,
          setup_status: setup_status,
        )

        expect(result).to be_nil
      end
    end
  end
end
