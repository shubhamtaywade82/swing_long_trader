# frozen_string_literal: true

require "rails_helper"

RSpec.describe Screeners::SwingScreener do
  let(:instrument) { create(:instrument, symbol_name: "TEST", instrument_type: "EQUITY") }
  let(:instruments) { Instrument.where(id: instrument.id) }

  describe ".call" do
    context "with instruments that have candles" do
      before do
        # Create daily candles for the instrument
        create_list(:candle_series_record, 60, instrument: instrument, timeframe: "1D")

        # Call the service once for tests that use default limit
        @result = described_class.call(instruments: instruments, limit: 10)
      end

      it "returns an array of candidates" do
        expect(@result).to be_an(Array)
      end

      it "respects the limit parameter" do
        # This test needs a different limit, so call separately
        result = described_class.call(instruments: instruments, limit: 5)
        expect(result.size).to be <= 5
      end

      it "returns candidates with required keys" do
        # This test needs limit: 1, so call separately
        result = described_class.call(instruments: instruments, limit: 1)
        next unless result.any?

        candidate = result.first
        expect(candidate).to have_key(:instrument_id)
        expect(candidate).to have_key(:symbol)
        expect(candidate).to have_key(:score)
        expect(candidate).to have_key(:indicators)
      end
    end

    context "with instruments without candles" do
      it "filters out instruments without candles" do
        instrument_no_candles = create(:instrument)
        instruments_without = Instrument.where(id: [instrument.id, instrument_no_candles.id])

        result = described_class.call(instruments: instruments_without, limit: 10)
        candidate_ids = result.pluck(:instrument_id)
        expect(candidate_ids).not_to include(instrument_no_candles.id)
      end
    end

    context "with price filters" do
      before do
        create_list(:candle_series_record, 60, instrument: instrument, timeframe: "1D")
      end

      it "filters instruments below minimum price" do
        allow_any_instance_of(Instrument).to receive(:ltp).and_return(10.0)

        # Mock config to require min_price of 50
        allow(AlgoConfig).to receive(:fetch).and_return({
          swing_trading: {
            screening: { min_price: 50 },
          },
        })

        result = described_class.call(instruments: instruments, limit: 10)
        # Instrument with LTP 10 should be filtered out
        expect(result.pluck(:symbol)).not_to include("TEST")
      end
    end

    context "with insufficient candles" do
      it "filters out instruments with less than 50 candles" do
        create_list(:candle_series_record, 30, instrument: instrument, timeframe: "1D")

        result = described_class.call(instruments: instruments, limit: 10)
        candidate_ids = result.pluck(:instrument_id)
        expect(candidate_ids).not_to include(instrument.id)
      end
    end

    context "with universe filtering" do
      it "loads from master_universe.yml if available" do
        universe_file = Rails.root.join("config/universe/master_universe.yml")
        allow(File).to receive(:exist?).with(universe_file).and_return(true)
        allow(YAML).to receive(:load_file).with(universe_file).and_return(%w[TEST OTHER])

        result = described_class.call(instruments: nil, limit: 10)
        expect(result).to be_an(Array)
      end

      it "falls back to all equity/index instruments if universe file not found" do
        universe_file = Rails.root.join("config/universe/master_universe.yml")
        allow(File).to receive(:exist?).with(universe_file).and_return(false)

        result = described_class.call(instruments: nil, limit: 10)
        expect(result).to be_an(Array)
      end
    end
  end

  describe "private methods" do
    let(:screener) { described_class.new(instruments: instruments) }

    describe "#passes_basic_filters?" do
      it "returns false for instruments without candles" do
        instrument_no_candles = create(:instrument)
        result = screener.send(:passes_basic_filters?, instrument_no_candles)
        expect(result).to be false
      end

      it "returns true for instruments with candles" do
        create_list(:candle_series_record, 10, instrument: instrument, timeframe: "1D")
        allow(instrument).to receive(:ltp).and_return(100.0)

        result = screener.send(:passes_basic_filters?, instrument)
        expect(result).to be true
      end

      it "filters instruments above max price" do
        create_list(:candle_series_record, 10, instrument: instrument, timeframe: "1D")
        allow(instrument).to receive(:ltp).and_return(60_000.0)
        allow(AlgoConfig).to receive(:fetch).and_return({
          swing_trading: {
            screening: { max_price: 50_000 },
          },
        })

        result = screener.send(:passes_basic_filters?, instrument)
        expect(result).to be false
      end

      it "filters penny stocks when enabled" do
        create_list(:candle_series_record, 10, instrument: instrument, timeframe: "1D")
        allow(instrument).to receive(:ltp).and_return(5.0)
        allow(AlgoConfig).to receive(:fetch).and_return({
          swing_trading: {
            screening: { exclude_penny_stocks: true },
          },
        })

        result = screener.send(:passes_basic_filters?, instrument)
        expect(result).to be false
      end
    end

    describe "#analyze_instrument" do
      it "returns nil when candles are insufficient" do
        create_list(:candle_series_record, 30, instrument: instrument, timeframe: "1D")
        allow(instrument).to receive(:load_daily_candles).and_return(
          CandleSeries.new(symbol: instrument.symbol_name, interval: "1D").tap do |cs|
            30.times { cs.add_candle(create(:candle)) }
          end,
        )

        result = screener.send(:analyze_instrument, instrument)
        expect(result).to be_nil
      end

      it "handles indicator calculation errors gracefully" do
        create_list(:candle_series_record, 60, instrument: instrument, timeframe: "1D")
        series = CandleSeries.new(symbol: instrument.symbol_name, interval: "1D")
        60.times { series.add_candle(create(:candle)) }
        allow(instrument).to receive(:load_daily_candles).and_return(series)
        allow(series).to receive(:ema).and_raise(StandardError, "Calculation error")
        allow(Rails.logger).to receive(:error)

        result = screener.send(:analyze_instrument, instrument)
        expect(result).to be_nil
        expect(Rails.logger).to have_received(:error)
      end

      it "handles supertrend calculation errors gracefully" do
        create_list(:candle_series_record, 60, instrument: instrument, timeframe: "1D")
        series = CandleSeries.new(symbol: instrument.symbol_name, interval: "1D")
        60.times { series.add_candle(create(:candle)) }
        allow(instrument).to receive(:load_daily_candles).and_return(series)
        allow(Indicators::Supertrend).to receive(:new).and_raise(StandardError, "Supertrend error")
        allow(Rails.logger).to receive(:warn)

        _result = screener.send(:analyze_instrument, instrument)
        # Should still return result even if supertrend fails
        expect(Rails.logger).to have_received(:warn)
      end
    end

    describe "#calculate_score" do
      let(:series) do
        cs = CandleSeries.new(symbol: instrument.symbol_name, interval: "1D")
        60.times { cs.add_candle(create(:candle)) }
        cs
      end

      before do
        allow(instrument).to receive(:load_daily_candles).and_return(series)
        allow(series).to receive_messages(ema: 100.0, rsi: 60.0, adx: 25.0, atr: 2.0, macd: [1.0, 0.5, 0.5])
        allow(Indicators::Supertrend).to receive(:new).and_return(
          double(call: { trend: :bullish, line: Array.new(60, 100.0) }),
        )
      end

      it "calculates score with EMA filters" do
        allow(AlgoConfig).to receive(:fetch).and_return({
          swing_trading: {
            strategy: {
              trend_filters: {
                use_ema20: true,
                use_ema50: true,
                use_ema200: true,
              },
            },
          },
        })

        screener = described_class.new(instruments: instruments)
        indicators = screener.send(:calculate_indicators, series)
        score = screener.send(:calculate_score, series, indicators)

        expect(score).to be >= 0
        expect(score).to be <= 100
      end

      it "calculates score with volume confirmation" do
        allow(AlgoConfig).to receive(:fetch).and_return({
          swing_trading: {
            strategy: {
              entry_conditions: {
                require_volume_confirmation: true,
                min_volume_spike: 1.5,
              },
            },
          },
        })

        screener = described_class.new(instruments: instruments)
        indicators = screener.send(:calculate_indicators, series)
        score = screener.send(:calculate_score, series, indicators)

        expect(score).to be >= 0
      end

      it "handles missing indicators gracefully" do
        screener = described_class.new(instruments: instruments)
        indicators = { ema20: nil, ema50: nil, rsi: nil }
        score = screener.send(:calculate_score, series, indicators)

        expect(score).to eq(0.0)
      end

      it "calculates score with different ADX levels" do
        screener = described_class.new(instruments: instruments)
        indicators = {
          ema20: 100.0,
          ema50: 95.0,
          adx: 30.0,
          rsi: 60.0,
          supertrend: { direction: :bullish },
          volume: { spike_ratio: 1.0 },
        }
        score = screener.send(:calculate_score, series, indicators)

        expect(score).to be > 0
      end
    end

    describe "#check_trend_alignment" do
      it "detects bullish EMA alignment" do
        screener = described_class.new(instruments: instruments)
        indicators = { ema20: 100.0, ema50: 95.0 }

        result = screener.send(:check_trend_alignment, indicators)

        expect(result).to include(:ema_bullish)
      end

      it "detects supertrend bullish alignment" do
        screener = described_class.new(instruments: instruments)
        indicators = { supertrend: { direction: :bullish } }

        result = screener.send(:check_trend_alignment, indicators)

        expect(result).to include(:supertrend_bullish)
      end

      it "detects MACD bullish alignment" do
        screener = described_class.new(instruments: instruments)
        indicators = { macd: [1.0, 0.5, 0.5] }

        result = screener.send(:check_trend_alignment, indicators)

        expect(result).to include(:macd_bullish)
      end
    end

    describe "#calculate_volatility" do
      it "calculates volatility metrics" do
        screener = described_class.new(instruments: instruments)
        indicators = { atr: 2.0, latest_close: 100.0 }

        result = screener.send(:calculate_volatility, series, indicators)

        expect(result).to have_key(:atr)
        expect(result).to have_key(:atr_percent)
        expect(result).to have_key(:level)
      end

      it "returns nil when indicators missing" do
        screener = described_class.new(instruments: instruments)
        indicators = {}

        result = screener.send(:calculate_volatility, series, indicators)

        expect(result).to be_nil
      end
    end

    describe "#calculate_momentum" do
      it "calculates momentum metrics" do
        screener = described_class.new(instruments: instruments)
        indicators = { rsi: 65.0 }

        result = screener.send(:calculate_momentum, series, indicators)

        expect(result).to have_key(:change_5d)
        expect(result).to have_key(:rsi)
        expect(result).to have_key(:level)
      end

      it "returns nil for insufficient candles" do
        small_series = CandleSeries.new(symbol: "TEST", interval: "1D")
        3.times { small_series.add_candle(create(:candle)) }
        screener = described_class.new(instruments: instruments)
        indicators = { rsi: 65.0 }

        result = screener.send(:calculate_momentum, small_series, indicators)

        expect(result).to be_nil
      end
    end

    context "with edge cases" do
      it "handles instruments without candles" do
        instrument_no_candles = create(:instrument)
        allow(instrument_no_candles).to receive(:has_candles?).and_return(false)

        instruments = Instrument.where(id: instrument_no_candles.id)
        result = described_class.call(instruments: instruments, limit: 10)

        expect(result).to be_empty
      end

      it "handles instruments with insufficient candles" do
        instrument = create(:instrument)
        allow(instrument).to receive_messages(has_candles?: true, load_daily_candles: CandleSeries.new(symbol: "TEST", interval: "1D").tap do |cs|
          30.times { cs.add_candle(create(:candle)) } # Less than 50 required
        end)

        instruments = Instrument.where(id: instrument.id)
        result = described_class.call(instruments: instruments, limit: 10)

        expect(result).to be_empty
      end

      it "handles nil LTP gracefully" do
        instrument = create(:instrument)
        allow(instrument).to receive_messages(has_candles?: true, ltp: nil, load_daily_candles: series)

        instruments = Instrument.where(id: instrument.id)
        result = described_class.call(instruments: instruments, limit: 10)

        # Should still process if LTP is nil
        expect(result).to be_an(Array)
      end

      it "handles penny stock exclusion" do
        instrument = create(:instrument)
        allow(instrument).to receive_messages(has_candles?: true, ltp: 5.0, load_daily_candles: series)

        allow(AlgoConfig).to receive(:fetch).and_return({
          swing_trading: {
            screening: {
              exclude_penny_stocks: true,
            },
          },
        })

        instruments = Instrument.where(id: instrument.id)
        result = described_class.call(instruments: instruments, limit: 10)

        expect(result).to be_empty
      end

      it "handles price range filters" do
        instrument = create(:instrument)
        allow(instrument).to receive_messages(has_candles?: true, ltp: 10.0, load_daily_candles: series)

        allow(AlgoConfig).to receive(:fetch).and_return({
          swing_trading: {
            screening: {
              min_price: 50,
              max_price: 50_000,
            },
          },
        })

        instruments = Instrument.where(id: instrument.id)
        result = described_class.call(instruments: instruments, limit: 10)

        expect(result).to be_empty
      end

      it "handles indicator calculation failures" do
        instrument = create(:instrument)
        allow(instrument).to receive_messages(has_candles?: true, load_daily_candles: series)
        allow(series).to receive(:ema).and_raise(StandardError.new("Calculation error"))
        allow(Rails.logger).to receive(:error)

        instruments = Instrument.where(id: instrument.id)
        result = described_class.call(instruments: instruments, limit: 10)

        expect(result).to be_empty
        expect(Rails.logger).to have_received(:error)
      end

      it "handles SMC validation failures" do
        instrument = create(:instrument)
        allow(instrument).to receive_messages(has_candles?: true, load_daily_candles: series)
        allow_any_instance_of(described_class).to receive(:validate_smc_structure).and_return({
          valid: false,
          reasons: ["Insufficient structure"],
        })

        instruments = Instrument.where(id: instrument.id)
        result = described_class.call(instruments: instruments, limit: 10)

        # Should still include candidate but with SMC validation info
        expect(result).to be_an(Array)
      end

      it "respects limit parameter" do
        instruments_list = create_list(:instrument, 100)
        instruments_list.each do |inst|
          allow(inst).to receive_messages(has_candles?: true, load_daily_candles: series)
        end

        instruments = Instrument.where(id: instruments_list.map(&:id))
        result = described_class.call(instruments: instruments, limit: 10)

        expect(result.size).to be <= 10
      end

      it "sorts candidates by score descending" do
        instrument1 = create(:instrument)
        instrument2 = create(:instrument)
        allow(instrument1).to receive_messages(has_candles?: true, load_daily_candles: series)
        allow(instrument2).to receive_messages(has_candles?: true, load_daily_candles: series)

        # Mock different scores
        allow_any_instance_of(described_class).to receive(:calculate_score).and_return(80, 90)

        instruments = Instrument.where(id: [instrument1.id, instrument2.id])
        result = described_class.call(instruments: instruments, limit: 10)

        expect(result[0][:score]).to be >= result[1][:score] if result.size >= 2
      end
    end

    describe "private methods" do
      let(:screener) { described_class.new(instruments: instruments) }

      describe "#load_universe" do
        it "loads from master_universe.yml if available" do
          universe_file = Rails.root.join("config/universe/master_universe.yml")
          allow(File).to receive(:exist?).with(universe_file).and_return(true)
          allow(YAML).to receive(:load_file).and_return(%w[RELIANCE TCS].to_set)

          result = screener.send(:load_universe)

          expect(result).to be_a(ActiveRecord::Relation)
        end

        it "falls back to all equity/index instruments" do
          universe_file = Rails.root.join("config/universe/master_universe.yml")
          allow(File).to receive(:exist?).with(universe_file).and_return(false)

          result = screener.send(:load_universe)

          expect(result).to be_a(ActiveRecord::Relation)
        end
      end

      describe "#passes_basic_filters?" do
        it "returns false when instrument has no candles" do
          instrument = create(:instrument)
          allow(instrument).to receive(:has_candles?).and_return(false)

          result = screener.send(:passes_basic_filters?, instrument)

          expect(result).to be false
        end

        it "returns false when price is below minimum" do
          instrument = create(:instrument)
          allow(instrument).to receive_messages(has_candles?: true, ltp: 10.0)

          allow(AlgoConfig).to receive(:fetch).and_return({
            swing_trading: {
              screening: {
                min_price: 50,
              },
            },
          })

          result = screener.send(:passes_basic_filters?, instrument)

          expect(result).to be false
        end

        it "returns false when price is above maximum" do
          instrument = create(:instrument)
          allow(instrument).to receive_messages(has_candles?: true, ltp: 100_000.0)

          allow(AlgoConfig).to receive(:fetch).and_return({
            swing_trading: {
              screening: {
                max_price: 50_000,
              },
            },
          })

          result = screener.send(:passes_basic_filters?, instrument)

          expect(result).to be false
        end
      end

      describe "#build_metadata" do
        it "builds metadata hash" do
          instrument = create(:instrument)
          indicators = { ema20: 100.0, rsi: 65.0 }
          smc_validation = { valid: true, score: 80 }

          metadata = screener.send(:build_metadata, instrument, series, indicators, smc_validation)

          expect(metadata).to be_a(Hash)
          expect(metadata).to have_key(:ltp)
          expect(metadata).to have_key(:volatility)
          expect(metadata).to have_key(:momentum)
        end
      end
    end
  end
end
