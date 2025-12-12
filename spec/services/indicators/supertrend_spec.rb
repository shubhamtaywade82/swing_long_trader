# frozen_string_literal: true

require "rails_helper"

RSpec.describe Indicators::Supertrend, type: :service do
  let(:series) { CandleSeries.new(symbol: "TEST", interval: "1D") }

  before do
    100.times do |i|
      series.add_candle(create(:candle, timestamp: i.days.ago))
    end
  end

  describe "#initialize" do
    it "initializes with default parameters" do
      indicator = described_class.new(series: series)

      expect(indicator.period).to eq(10)
      expect(indicator.base_multiplier).to eq(2.0)
      expect(indicator.training_period).to eq(50)
    end

    it "uses custom parameters" do
      indicator = described_class.new(
        series: series,
        period: 14,
        base_multiplier: 3.0,
        training_period: 30,
      )

      expect(indicator.period).to eq(14)
      expect(indicator.base_multiplier).to eq(3.0)
      expect(indicator.training_period).to eq(30)
    end
  end

  describe "#call" do
    context "when series has sufficient candles" do
      it "calculates supertrend" do
        indicator = described_class.new(series: series)
        result = indicator.call

        expect(result).to be_present
        expect(result).to have_key(:line)
        expect(result).to have_key(:trend)
        expect(result).to have_key(:atr)
      end

      it "returns trend direction" do
        indicator = described_class.new(series: series)
        result = indicator.call

        expect(result[:trend]).to be_in(%i[bullish bearish])
      end
    end

    context "when series has insufficient candles" do
      let(:small_series) { CandleSeries.new(symbol: "TEST", interval: "1D") }

      before do
        20.times { small_series.add_candle(create(:candle)) }
      end

      it "returns default result" do
        indicator = described_class.new(series: small_series, training_period: 50)
        result = indicator.call

        expect(result[:line]).to be_empty
        expect(result[:trend]).to be_nil
      end
    end

    context "when series is empty" do
      let(:empty_series) { CandleSeries.new(symbol: "TEST", interval: "1D") }

      it "returns default result" do
        indicator = described_class.new(series: empty_series)
        result = indicator.call

        expect(result[:line]).to be_empty
      end
    end
  end

  describe "#get_current_volatility_regime" do
    before do
      allow_any_instance_of(described_class).to receive(:call).and_return(
        { line: Array.new(100, 100.0), trend: :bullish },
      )
    end

    it "returns volatility regime" do
      indicator = described_class.new(series: series)
      indicator.call

      regime = indicator.get_current_volatility_regime(60)

      expect(regime).to be_in(%i[low medium high unknown])
    end

    context "when index is before training period" do
      it "returns unknown" do
        indicator = described_class.new(series: series, training_period: 50)
        indicator.call

        regime = indicator.get_current_volatility_regime(30)

        expect(regime).to eq(:unknown)
      end
    end

    it "returns low volatility for multiplier below base" do
      indicator = described_class.new(series: series, base_multiplier: 2.0)
      indicator.instance_variable_set(:@adaptive_multipliers, Array.new(100, 1.5))
      indicator.call

      regime = indicator.get_current_volatility_regime(60)

      expect(regime).to eq(:low)
    end

    it "returns medium volatility for multiplier near base" do
      indicator = described_class.new(series: series, base_multiplier: 2.0)
      indicator.instance_variable_set(:@adaptive_multipliers, Array.new(100, 2.5))
      indicator.call

      regime = indicator.get_current_volatility_regime(60)

      expect(regime).to eq(:medium)
    end

    it "returns high volatility for multiplier well above base" do
      indicator = described_class.new(series: series, base_multiplier: 2.0)
      indicator.instance_variable_set(:@adaptive_multipliers, Array.new(100, 3.0))
      indicator.call

      regime = indicator.get_current_volatility_regime(60)

      expect(regime).to eq(:high)
    end

    it "returns unknown for nil index" do
      indicator = described_class.new(series: series)
      indicator.call

      regime = indicator.get_current_volatility_regime(nil)

      expect(regime).to eq(:unknown)
    end
  end

  describe "#get_performance_metrics" do
    before do
      allow_any_instance_of(described_class).to receive(:call).and_return(
        { line: Array.new(100, 100.0), trend: :bullish },
      )
    end

    it "returns performance metrics" do
      indicator = described_class.new(series: series)
      indicator.call

      metrics = indicator.get_performance_metrics

      expect(metrics).to have_key(:multiplier_scores)
      expect(metrics).to have_key(:total_clusters)
      expect(metrics).to have_key(:training_period)
    end
  end

  describe "#get_adaptive_multiplier" do
    before do
      allow_any_instance_of(described_class).to receive(:call).and_return(
        { line: Array.new(100, 100.0), trend: :bullish },
      )
    end

    it "returns adaptive multiplier for index" do
      indicator = described_class.new(series: series)
      indicator.call

      multiplier = indicator.get_adaptive_multiplier(50)

      expect(multiplier).to be_a(Numeric)
      expect(multiplier).to be > 0
    end

    context "when index is out of range" do
      it "returns base multiplier" do
        indicator = described_class.new(series: series)
        indicator.call

        multiplier = indicator.get_adaptive_multiplier(999)

        expect(multiplier).to eq(2.0) # base_multiplier
      end
    end

    it "returns multiplier for valid index" do
      indicator = described_class.new(series: series)
      indicator.instance_variable_set(:@adaptive_multipliers, Array.new(100, 2.5))
      indicator.call

      multiplier = indicator.get_adaptive_multiplier(50)

      expect(multiplier).to eq(2.5)
    end

    it "returns base multiplier for out of range index" do
      indicator = described_class.new(series: series, base_multiplier: 3.0)
      indicator.call

      multiplier = indicator.get_adaptive_multiplier(999)

      expect(multiplier).to eq(3.0)
    end

    context "private methods" do
      describe "#calculate_adaptive_atr" do
        it "handles nil values in highs and lows" do
          indicator = described_class.new(series: series)
          highs = [100.0, nil, 105.0]
          lows = [99.0, nil, 104.0]
          closes = [100.0, 102.0, 105.0]

          result = indicator.send(:calculate_adaptive_atr, highs, lows, closes)

          expect(result).to be_an(Array)
        end

        it "calculates true range for first candle" do
          indicator = described_class.new(series: series)
          highs = [105.0, 106.0]
          lows = [99.0, 100.0]
          closes = [100.0, 102.0]

          result = indicator.send(:calculate_adaptive_atr, highs, lows, closes)

          expect(result[0]).to eq(6.0) # high - low for first candle
        end

        it "handles missing previous close" do
          indicator = described_class.new(series: series)
          highs = [100.0, 105.0]
          lows = [99.0, 104.0]
          closes = [nil, 102.0]

          result = indicator.send(:calculate_adaptive_atr, highs, lows, closes)

          expect(result).to be_an(Array)
        end
      end

      describe "#calculate_volatility_factor" do
        it "returns 1.0 for index before 20" do
          indicator = described_class.new(series: series)
          closes = Array.new(100, 100.0)

          result = indicator.send(:calculate_volatility_factor, closes, 10)

          expect(result).to eq(1.0)
        end

        it "returns 1.0 for index out of range" do
          indicator = described_class.new(series: series)
          closes = Array.new(50, 100.0)

          result = indicator.send(:calculate_volatility_factor, closes, 100)

          expect(result).to eq(1.0)
        end

        it "handles zero historical volatility" do
          indicator = described_class.new(series: series)
          closes = Array.new(100, 100.0) # No volatility

          result = indicator.send(:calculate_volatility_factor, closes, 50)

          expect(result).to eq(1.0)
        end
      end

      describe "#returns_for_window" do
        it "returns empty array for nil window" do
          indicator = described_class.new(series: series)

          result = indicator.send(:returns_for_window, nil)

          expect(result).to eq([])
        end

        it "handles zero prices" do
          indicator = described_class.new(series: series)
          window = [0.0, 100.0, 105.0]

          result = indicator.send(:returns_for_window, window)

          expect(result).to be_an(Array)
        end
      end

      describe "#optimize_multipliers_with_clustering" do
        it "returns early if size <= training_period" do
          small_series = CandleSeries.new(symbol: "TEST", interval: "1D")
          30.times { small_series.add_candle(create(:candle)) }
          indicator = described_class.new(series: small_series, training_period: 50)
          closes = Array.new(30, 100.0)
          atr = Array.new(30, 2.0)

          result = indicator.send(:optimize_multipliers_with_clustering, closes, atr)

          expect(result).to eq(indicator.adaptive_multipliers)
        end
      end
    end
  end

  describe "edge cases" do
    it "handles series with highs/lows/closes methods" do
      series_with_methods = double("series",
                                   highs: [100.0, 105.0],
                                   lows: [99.0, 104.0],
                                   closes: [100.0, 102.0])
      indicator = described_class.new(series: series_with_methods, training_period: 1)

      result = indicator.call

      expect(result).to be_present
    end

    it "handles series without expected methods" do
      invalid_series = double("series")
      indicator = described_class.new(series: invalid_series)

      result = indicator.call

      expect(result[:line]).to be_empty
    end

    it "handles nil values in series" do
      series_nil = CandleSeries.new(symbol: "TEST", interval: "1D")
      series_nil.add_candle(create(:candle, high: nil, low: nil, close: nil))
      indicator = described_class.new(series: series_nil, training_period: 1)

      result = indicator.call

      expect(result[:line]).to be_empty
    end
  end
end
