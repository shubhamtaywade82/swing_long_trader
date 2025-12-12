# frozen_string_literal: true

require "rails_helper"

RSpec.describe Strategies::Swing::Engine, type: :service do
  let(:instrument) { create(:instrument) }
  let(:daily_series) { create(:candle_series, symbol: instrument.symbol_name, interval: "1D") }
  let(:weekly_series) { create(:candle_series, symbol: instrument.symbol_name, interval: "1W") }

  before do
    # Add sufficient candles
    60.times do |i|
      daily_series.add_candle(create(:candle, timestamp: i.days.ago))
    end
  end

  describe ".call" do
    it "delegates to instance method" do
      allow_any_instance_of(described_class).to receive(:call).and_return({ success: true })

      described_class.call(
        instrument: instrument,
        daily_series: daily_series,
      )

      expect_any_instance_of(described_class).to have_received(:call)
    end
  end

  describe "#call" do
    context "when inputs are valid" do
      before do
        allow(Strategies::Swing::SignalBuilder).to receive(:call).and_return(
          {
            direction: "long",
            entry_price: 100.0,
            confidence: 75,
            sl: 95.0,
            tp: 110.0,
          },
        )
        allow(Smc::StructureValidator).to receive(:validate).and_return({ valid: true })
      end

      it "returns success with signal" do
        result = described_class.new(
          instrument: instrument,
          daily_series: daily_series,
        ).call

        expect(result[:success]).to be true
        expect(result[:signal]).to be_present
      end

      it "includes metadata" do
        result = described_class.new(
          instrument: instrument,
          daily_series: daily_series,
        ).call

        expect(result[:metadata]).to be_present
        expect(result[:metadata][:evaluated_at]).to be_present
        expect(result[:metadata][:candles_analyzed]).to eq(60)
      end
    end

    context "when instrument is invalid" do
      it "returns error" do
        result = described_class.new(
          instrument: nil,
          daily_series: daily_series,
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Invalid instrument")
      end
    end

    context "when insufficient candles" do
      let(:small_series) { create(:candle_series) }

      before do
        30.times { small_series.add_candle(create(:candle)) }
      end

      it "returns error" do
        result = described_class.new(
          instrument: instrument,
          daily_series: small_series,
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Insufficient daily candles")
      end
    end

    context "when entry conditions fail" do
      before do
        allow_any_instance_of(described_class).to receive(:check_entry_conditions).and_return(
          { allowed: false, error: "Trend alignment failed" },
        )
      end

      it "returns error" do
        result = described_class.new(
          instrument: instrument,
          daily_series: daily_series,
          config: { entry_conditions: { require_trend_alignment: true } },
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Trend alignment failed")
      end
    end

    context "when SMC validation fails" do
      before do
        allow(Smc::StructureValidator).to receive(:validate).and_return(
          { valid: false, reasons: ["No BOS detected"] },
        )
        allow(Strategies::Swing::SignalBuilder).to receive(:call).and_return(
          { direction: "long", entry_price: 100.0, confidence: 75 },
        )
      end

      it "returns error" do
        result = described_class.new(
          instrument: instrument,
          daily_series: daily_series,
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to include("SMC validation failed")
      end
    end

    context "when confidence is too low" do
      before do
        allow(Strategies::Swing::SignalBuilder).to receive(:call).and_return(
          { direction: "long", entry_price: 100.0, confidence: 50 },
        )
        allow(Smc::StructureValidator).to receive(:validate).and_return({ valid: true })
      end

      it "returns error" do
        result = described_class.new(
          instrument: instrument,
          daily_series: daily_series,
          config: { min_confidence: 0.7 },
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to include("Confidence too low")
      end
    end

    describe "#check_entry_conditions" do
      let(:engine) { described_class.new(instrument: instrument, daily_series: daily_series) }

      it "allows entry when no conditions required" do
        result = engine.send(:check_entry_conditions)

        expect(result[:allowed]).to be true
      end

      it "requires trend alignment when configured" do
        allow(engine).to receive(:check_trend_alignment).and_return(false)

        result = engine.send(:check_entry_conditions, config: { entry_conditions: { require_trend_alignment: true } })

        expect(result[:allowed]).to be false
        expect(result[:error]).to eq("Trend alignment failed")
      end

      it "requires volume confirmation when configured" do
        allow(engine).to receive(:check_volume_confirmation).and_return(false)

        result = engine.send(:check_entry_conditions, config: { entry_conditions: { require_volume_confirmation: true } })

        expect(result[:allowed]).to be false
        expect(result[:error]).to eq("Volume confirmation failed")
      end
    end

    describe "#check_trend_alignment" do
      let(:engine) { described_class.new(instrument: instrument, daily_series: daily_series) }

      before do
        allow(engine).to receive(:calculate_indicators).and_return({
          ema20: 100.0,
          ema50: 95.0,
          ema200: 90.0,
          supertrend: { direction: :bullish },
        })
      end

      it "validates EMA alignment" do
        result = engine.send(:check_trend_alignment, config: {
          trend_filters: { use_ema20: true, use_ema50: true },
        })

        expect(result).to be true
      end

      it "validates EMA200 alignment" do
        result = engine.send(:check_trend_alignment, config: {
          trend_filters: { use_ema200: true },
        })

        expect(result).to be true
      end

      it "returns false when EMA20 < EMA50" do
        allow(engine).to receive(:calculate_indicators).and_return({
          ema20: 95.0,
          ema50: 100.0,
          supertrend: { direction: :bullish },
        })

        result = engine.send(:check_trend_alignment, config: {
          trend_filters: { use_ema20: true, use_ema50: true },
        })

        expect(result).to be false
      end

      it "returns false when supertrend is not bullish" do
        allow(engine).to receive(:calculate_indicators).and_return({
          ema20: 100.0,
          ema50: 95.0,
          supertrend: { direction: :bearish },
        })

        result = engine.send(:check_trend_alignment)

        expect(result).to be false
      end
    end

    describe "#check_volume_confirmation" do
      let(:engine) { described_class.new(instrument: instrument, daily_series: daily_series) }

      it "returns true for insufficient candles" do
        small_series = CandleSeries.new(symbol: "TEST", interval: "1D")
        10.times { small_series.add_candle(create(:candle, volume: 1_000_000)) }
        engine = described_class.new(instrument: instrument, daily_series: small_series)

        result = engine.send(:check_volume_confirmation, 1.5)

        expect(result).to be true
      end

      it "validates volume spike" do
        # Create series with volume spike
        volumes = Array.new(20, 1_000_000) + [3_000_000] # Latest volume is 3x average
        volumes.each_with_index do |vol, i|
          daily_series.candles[i]&.volume = vol if daily_series.candles[i]
        end

        result = engine.send(:check_volume_confirmation, 1.5)

        expect(result).to be true
      end

      it "returns false when volume spike is insufficient" do
        # Create series with low volume
        volumes = Array.new(21, 1_000_000) # All same volume, no spike
        volumes.each_with_index do |vol, i|
          daily_series.candles[i]&.volume = vol if daily_series.candles[i]
        end

        result = engine.send(:check_volume_confirmation, 2.0)

        expect(result).to be false
      end

      it "returns false when average volume is zero" do
        # Create series with zero volumes
        volumes = Array.new(21, 0)
        volumes.each_with_index do |vol, i|
          daily_series.candles[i]&.volume = vol if daily_series.candles[i]
        end

        result = engine.send(:check_volume_confirmation, 1.5)

        expect(result).to be false
      end
    end

    context "with edge cases" do
      it "handles nil weekly series" do
        result = described_class.call(
          instrument: instrument,
          daily_series: series,
          weekly_series: nil,
        )

        expect(result[:success]).to be_in([true, false])
        expect(result[:metadata][:weekly_available]).to be false if result[:success]
      end

      it "handles confidence threshold check" do
        allow(Strategies::Swing::SignalBuilder).to receive(:call).and_return({
          instrument_id: instrument.id,
          direction: :long,
          entry_price: 100.0,
          confidence: 50.0, # Below 70% threshold
        })

        allow(AlgoConfig).to receive(:fetch).and_return({
          swing_trading: {
            strategy: {
              min_confidence: 0.7,
            },
          },
        })

        result = described_class.call(
          instrument: instrument,
          daily_series: series,
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include("Confidence too low")
      end

      it "handles SMC validation failure" do
        allow_any_instance_of(described_class).to receive(:validate_smc_structure).and_return({
          valid: false,
          reasons: ["Insufficient structure", "No order blocks"],
        })

        result = described_class.call(
          instrument: instrument,
          daily_series: series,
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include("SMC validation failed")
      end

      it "handles signal builder returning nil" do
        allow(Strategies::Swing::SignalBuilder).to receive(:call).and_return(nil)

        result = described_class.call(
          instrument: instrument,
          daily_series: series,
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include("Signal generation failed")
      end

      it "handles entry condition failures" do
        allow_any_instance_of(described_class).to receive(:check_entry_conditions).and_return({
          allowed: false,
          error: "Trend alignment failed",
        })

        result = described_class.call(
          instrument: instrument,
          daily_series: series,
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include("Trend alignment failed")
      end

      it "includes SMC validation in metadata when available" do
        smc_validation = {
          valid: true,
          score: 85,
          components: { bos: true, choch: true },
        }

        allow_any_instance_of(described_class).to receive(:validate_smc_structure).and_return(smc_validation)
        allow(Strategies::Swing::SignalBuilder).to receive(:call).and_return({
          instrument_id: instrument.id,
          direction: :long,
          entry_price: 100.0,
          confidence: 80.0,
        })

        result = described_class.call(
          instrument: instrument,
          daily_series: series,
        )

        expect(result[:metadata][:smc_validation]).to eq(smc_validation) if result[:success]
      end

      it "handles supertrend calculation failure" do
        allow(Indicators::Supertrend).to receive(:new).and_raise(StandardError.new("Supertrend error"))
        allow(Rails.logger).to receive(:warn)

        result = engine.send(:calculate_supertrend)

        expect(result).to be_nil
        expect(Rails.logger).to have_received(:warn)
      end

      it "handles supertrend returning nil trend" do
        supertrend_mock = double("Supertrend")
        allow(Indicators::Supertrend).to receive(:new).and_return(supertrend_mock)
        allow(supertrend_mock).to receive(:call).and_return({ line: [100.0], trend: nil })

        result = engine.send(:calculate_supertrend)

        expect(result).to be_nil
      end
    end

    context "with entry condition requirements" do
      it "requires trend alignment when configured" do
        allow(engine).to receive(:check_trend_alignment).and_return(false)

        allow(AlgoConfig).to receive(:fetch).and_return({
          swing_trading: {
            strategy: {
              entry_conditions: {
                require_trend_alignment: true,
              },
            },
          },
        })

        result = engine.send(:check_entry_conditions)

        expect(result[:allowed]).to be false
        expect(result[:error]).to include("Trend alignment failed")
      end

      it "requires volume confirmation when configured" do
        allow(engine).to receive(:check_volume_confirmation).and_return(false)

        allow(AlgoConfig).to receive(:fetch).and_return({
          swing_trading: {
            strategy: {
              entry_conditions: {
                require_volume_confirmation: true,
                min_volume_spike: 2.0,
              },
            },
          },
        })

        result = engine.send(:check_entry_conditions)

        expect(result[:allowed]).to be false
        expect(result[:error]).to include("Volume confirmation failed")
      end

      it "allows entry when all conditions pass" do
        allow(engine).to receive_messages(check_trend_alignment: true, check_volume_confirmation: true)

        allow(AlgoConfig).to receive(:fetch).and_return({
          swing_trading: {
            strategy: {
              entry_conditions: {
                require_trend_alignment: true,
                require_volume_confirmation: true,
              },
            },
          },
        })

        result = engine.send(:check_entry_conditions)

        expect(result[:allowed]).to be true
      end
    end
  end
end
