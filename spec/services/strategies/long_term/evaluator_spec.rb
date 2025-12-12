# frozen_string_literal: true

require "rails_helper"

RSpec.describe Strategies::LongTerm::Evaluator, type: :service do
  let(:instrument) { create(:instrument) }
  let(:candidate) do
    {
      instrument_id: instrument.id,
      symbol: instrument.symbol_name,
      score: 85,
    }
  end

  describe ".call" do
    it "delegates to instance method" do
      allow_any_instance_of(described_class).to receive(:call).and_return({ success: true })

      described_class.call(candidate)

      expect_any_instance_of(described_class).to have_received(:call)
    end
  end

  describe "#call" do
    context "when candidate is valid" do
      let(:daily_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "1D") }
      let(:weekly_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "1W") }

      before do
        200.times { daily_series.add_candle(create(:candle)) }
        52.times { weekly_series.add_candle(create(:candle)) }

        allow(instrument).to receive_messages(load_daily_candles: daily_series, load_weekly_candles: weekly_series)
        allow(AlgoConfig).to receive(:fetch).and_return({})
      end

      it "loads candles and builds signal" do
        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be true
        expect(result[:signal]).to be_present
        expect(result[:signal][:direction]).to eq(:long)
      end

      it "includes metadata" do
        result = described_class.new(candidate: candidate).call

        expect(result[:metadata]).to be_present
        expect(result[:metadata][:daily_candles]).to eq(200)
        expect(result[:metadata][:weekly_candles]).to eq(52)
      end
    end

    context "when candidate is invalid" do
      it "returns error" do
        result = described_class.new(candidate: nil).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Invalid candidate")
      end
    end

    context "when instrument is not found" do
      let(:candidate) { { instrument_id: 99_999, symbol: "INVALID" } }

      it "returns error" do
        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Instrument not found")
      end
    end

    context "when candles fail to load" do
      before do
        allow(instrument).to receive(:load_daily_candles).and_return(nil)
      end

      it "returns error" do
        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Failed to load candles")
      end
    end

    context "when entry conditions fail" do
      let(:daily_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "1D") }
      let(:weekly_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "1W") }

      before do
        200.times { daily_series.add_candle(create(:candle)) }
        52.times { weekly_series.add_candle(create(:candle)) }

        allow(instrument).to receive_messages(load_daily_candles: daily_series, load_weekly_candles: weekly_series)
        allow(AlgoConfig).to receive(:fetch).and_return(
          long_term_trading: {
            strategy: {
              entry_conditions: {
                require_weekly_trend: true,
              },
            },
          },
        )
        allow(daily_series).to receive(:ema).and_return(100.0)
        allow(weekly_series).to receive(:ema).and_return(95.0) # EMA20 < EMA50 (fails)
      end

      it "returns error" do
        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to include("Weekly EMA not aligned")
      end
    end

    context "with edge cases" do
      let(:daily_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "1D") }
      let(:weekly_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "1W") }

      before do
        200.times { daily_series.add_candle(create(:candle)) }
        52.times { weekly_series.add_candle(create(:candle)) }

        allow(instrument).to receive_messages(load_daily_candles: daily_series, load_weekly_candles: weekly_series)
      end

      it "handles empty daily candles array" do
        empty_series = CandleSeries.new(symbol: instrument.symbol_name, interval: "1D")
        allow(instrument).to receive(:load_daily_candles).and_return(empty_series)

        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Failed to load candles")
      end

      it "handles empty weekly candles array" do
        empty_weekly = CandleSeries.new(symbol: instrument.symbol_name, interval: "1W")
        allow(instrument).to receive(:load_weekly_candles).and_return(empty_weekly)

        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Failed to load weekly candles")
      end

      it "handles nil weekly series" do
        allow(instrument).to receive(:load_weekly_candles).and_return(nil)

        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Failed to load weekly candles")
      end

      it "handles entry condition with momentum score requirement" do
        allow(AlgoConfig).to receive(:fetch).and_return(
          long_term_trading: {
            strategy: {
              entry_conditions: {
                min_momentum_score: 0.8,
              },
            },
          },
        )
        allow(daily_series).to receive_messages(ema: 100.0, rsi: 40.0, adx: 15.0) # Low ADX
        allow(weekly_series).to receive_messages(ema: 100.0, rsi: 40.0, adx: 15.0)

        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to include("Momentum too low")
      end

      it "handles weekly trend requirement with nil indicators" do
        allow(AlgoConfig).to receive(:fetch).and_return(
          long_term_trading: {
            strategy: {
              entry_conditions: {
                require_weekly_trend: true,
              },
            },
          },
        )
        allow(weekly_series).to receive(:ema).and_return(nil)

        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to include("Weekly trend not bullish")
      end

      it "handles signal generation with nil latest close" do
        allow(daily_series.candles).to receive(:last).and_return(nil)

        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to include("Signal generation failed")
      end

      it "calculates position size correctly" do
        allow(AlgoConfig).to receive(:fetch).and_return(
          risk: {
            risk_per_trade_pct: 2.0,
            account_size: 100_000,
          },
        )

        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be true
        expect(result[:signal][:qty]).to be > 0
      end

      it "handles lot size rounding" do
        instrument.update!(lot_size: 50)
        allow(AlgoConfig).to receive(:fetch).and_return(
          risk: {
            risk_per_trade_pct: 2.0,
            account_size: 100_000,
          },
        )

        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be true
        # Quantity should be multiple of lot_size
        expect(result[:signal][:qty] % 50).to eq(0)
      end

      it "ensures minimum quantity of 1" do
        allow(AlgoConfig).to receive(:fetch).and_return(
          risk: {
            risk_per_trade_pct: 0.001, # Very small risk
            account_size: 1000, # Small account
          },
        )

        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be true
        expect(result[:signal][:qty]).to be >= 1
      end

      it "handles zero risk per share" do
        # Create candles where entry_price == stop_loss
        allow(daily_series.candles).to receive(:last).and_return(
          double("Candle", close: 100.0),
        )
        allow(AlgoConfig).to receive(:fetch).and_return(
          long_term_trading: {
            strategy: {
              exit_conditions: {
                stop_loss_pct: 0.0, # No stop loss
              },
            },
          },
          risk: {
            risk_per_trade_pct: 2.0,
            account_size: 100_000,
          },
        )

        result = described_class.new(candidate: candidate).call

        # Should handle zero risk per share (returns 0 quantity or minimum 1)
        expect(result[:signal][:qty]).to be >= 0
      end
    end

    describe "private methods" do
      let(:evaluator) { described_class.new(candidate: candidate) }
      let(:daily_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "1D") }
      let(:weekly_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "1W") }

      before do
        200.times { daily_series.add_candle(create(:candle)) }
        52.times { weekly_series.add_candle(create(:candle)) }
        allow(instrument).to receive_messages(load_daily_candles: daily_series, load_weekly_candles: weekly_series)
      end

      describe "#calculate_indicators" do
        it "calculates all indicators" do
          allow(daily_series).to receive_messages(ema: 100.0, rsi: 65.0, adx: 25.0)

          indicators = evaluator.send(:calculate_indicators, daily_series)

          expect(indicators).to have_key(:ema20)
          expect(indicators).to have_key(:ema50)
          expect(indicators).to have_key(:ema200)
          expect(indicators).to have_key(:rsi)
          expect(indicators).to have_key(:adx)
        end
      end

      describe "#calculate_momentum_score" do
        it "calculates momentum score based on RSI and ADX" do
          allow(daily_series).to receive_messages(ema: 100.0, rsi: 65.0, adx: 25.0) # > 20
          allow(weekly_series).to receive_messages(ema: 100.0, rsi: 60.0, adx: 22.0) # > 20

          score = evaluator.send(:calculate_momentum_score, daily_series, weekly_series)

          # Daily RSI (0.2) + Weekly RSI (0.2) + Daily ADX (0.3) + Weekly ADX (0.3) = 1.0
          expect(score).to eq(1.0)
        end

        it "handles nil indicators" do
          allow(daily_series).to receive_messages(ema: 100.0, rsi: nil, adx: nil)
          allow(weekly_series).to receive_messages(ema: 100.0, rsi: nil, adx: nil)

          score = evaluator.send(:calculate_momentum_score, daily_series, weekly_series)

          expect(score).to eq(0.0)
        end

        it "handles indicators below thresholds" do
          allow(daily_series).to receive_messages(ema: 100.0, rsi: 40.0, adx: 15.0) # < 20
          allow(weekly_series).to receive_messages(ema: 100.0, rsi: 45.0, adx: 18.0) # < 20

          score = evaluator.send(:calculate_momentum_score, daily_series, weekly_series)

          expect(score).to eq(0.0)
        end
      end

      describe "#build_long_term_signal" do
        it "builds signal with correct structure" do
          allow(daily_series.candles).to receive(:last).and_return(
            double("Candle", close: 100.0),
          )
          allow(AlgoConfig).to receive(:fetch).and_return(
            long_term_trading: {
              strategy: {
                exit_conditions: {
                  profit_target_pct: 30.0,
                  stop_loss_pct: 15.0,
                },
                holding_period_days: 30,
              },
            },
            risk: {
              risk_per_trade_pct: 2.0,
              account_size: 100_000,
            },
          )

          signal = evaluator.send(:build_long_term_signal, daily_series, weekly_series)

          expect(signal).to have_key(:instrument_id)
          expect(signal).to have_key(:direction)
          expect(signal).to have_key(:entry_price)
          expect(signal).to have_key(:sl)
          expect(signal).to have_key(:tp)
          expect(signal).to have_key(:rr)
          expect(signal).to have_key(:qty)
          expect(signal[:direction]).to eq(:long)
        end

        it "calculates stop loss and take profit correctly" do
          allow(daily_series.candles).to receive(:last).and_return(
            double("Candle", close: 100.0),
          )
          allow(AlgoConfig).to receive(:fetch).and_return(
            long_term_trading: {
              strategy: {
                exit_conditions: {
                  profit_target_pct: 30.0,
                  stop_loss_pct: 15.0,
                },
              },
            },
            risk: {
              risk_per_trade_pct: 2.0,
              account_size: 100_000,
            },
          )

          signal = evaluator.send(:build_long_term_signal, daily_series, weekly_series)

          expect(signal[:entry_price]).to eq(100.0)
          expect(signal[:sl]).to eq(85.0) # 100 * (1 - 0.15)
          expect(signal[:tp]).to eq(130.0) # 100 * (1 + 0.30)
        end

        it "calculates risk-reward ratio correctly" do
          allow(daily_series.candles).to receive(:last).and_return(
            double("Candle", close: 100.0),
          )
          allow(AlgoConfig).to receive(:fetch).and_return(
            long_term_trading: {
              strategy: {
                exit_conditions: {
                  profit_target_pct: 30.0,
                  stop_loss_pct: 15.0,
                },
              },
            },
            risk: {
              risk_per_trade_pct: 2.0,
              account_size: 100_000,
            },
          )

          signal = evaluator.send(:build_long_term_signal, daily_series, weekly_series)

          # RR = (130 - 100) / (100 - 85) = 30 / 15 = 2.0
          expect(signal[:rr]).to eq(2.0)
        end

        it "uses default values when config missing" do
          allow(daily_series.candles).to receive(:last).and_return(
            double("Candle", close: 100.0),
          )
          allow(AlgoConfig).to receive(:fetch).and_return({})

          signal = evaluator.send(:build_long_term_signal, daily_series, weekly_series)

          expect(signal[:sl]).to eq(85.0) # Default 15% stop loss
          expect(signal[:tp]).to eq(130.0) # Default 30% profit target
          expect(signal[:holding_days_estimate]).to eq(30) # Default
        end
      end

      describe "#calculate_position_size" do
        it "calculates position size based on risk" do
          allow(AlgoConfig).to receive(:fetch).and_return(
            risk: {
              risk_per_trade_pct: 2.0,
              account_size: 100_000,
            },
          )

          # Risk amount: 100,000 * 0.02 = 2,000
          # Risk per share: 100 - 85 = 15
          # Quantity: 2,000 / 15 = 133.33 -> 133
          quantity = evaluator.send(:calculate_position_size, 100.0, 85.0)

          expect(quantity).to eq(133)
        end

        it "handles lot size rounding" do
          instrument.update!(lot_size: 50)
          allow(AlgoConfig).to receive(:fetch).and_return(
            risk: {
              risk_per_trade_pct: 2.0,
              account_size: 100_000,
            },
          )

          quantity = evaluator.send(:calculate_position_size, 100.0, 85.0)

          # Should round to nearest lot size (133 -> 100 or 150)
          expect(quantity % 50).to eq(0)
        end

        it "ensures minimum quantity of 1" do
          allow(AlgoConfig).to receive(:fetch).and_return(
            risk: {
              risk_per_trade_pct: 0.001,
              account_size: 1000,
            },
          )

          quantity = evaluator.send(:calculate_position_size, 100.0, 85.0)

          expect(quantity).to be >= 1
        end

        it "handles zero risk per share" do
          allow(AlgoConfig).to receive(:fetch).and_return(
            risk: {
              risk_per_trade_pct: 2.0,
              account_size: 100_000,
            },
          )

          quantity = evaluator.send(:calculate_position_size, 100.0, 100.0)

          expect(quantity).to eq(0)
        end

        it "uses default risk config when missing" do
          allow(AlgoConfig).to receive(:fetch).and_return({})

          quantity = evaluator.send(:calculate_position_size, 100.0, 85.0)

          # Should use defaults: risk_pct = 2.0, account_size = 100,000
          expect(quantity).to be > 0
        end
      end
    end
  end
end
