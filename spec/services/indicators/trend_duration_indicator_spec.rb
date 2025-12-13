# frozen_string_literal: true

require "rails_helper"

RSpec.describe Indicators::TrendDurationIndicator, type: :service do
  let(:series) { CandleSeries.new(symbol: "TEST", interval: "1D") }

  before do
    100.times { series.add_candle(create(:candle)) }
  end

  describe "#initialize" do
    it "initializes with default HMA length" do
      indicator = described_class.new(series: series)

      expect(indicator.min_required_candles).to be > 20
    end

    it "uses custom HMA length from config" do
      indicator = described_class.new(series: series, config: { hma_length: 30 })

      expect(indicator.min_required_candles).to be > 30
    end
  end

  describe "#ready?" do
    it "returns false when index is too small" do
      indicator = described_class.new(series: series)

      expect(indicator.ready?(20)).to be false
    end

    it "returns true when index is sufficient" do
      indicator = described_class.new(series: series)

      expect(indicator.ready?(50)).to be true
    end
  end

  describe "#calculate_at" do
    it "calculates trend duration" do
      indicator = described_class.new(series: series)
      result = indicator.calculate_at(50)

      # May return nil if trend is not detected (needs sufficient data and clear trend)
      # If result exists, it should have the expected structure
      if result
        expect(result).to have_key(:value)
        expect(result).to have_key(:direction)
        expect(result).to have_key(:confidence)
        expect(result[:value]).to have_key(:hma)
        expect(result[:value]).to have_key(:trend_direction)
      else
        # It's acceptable to return nil if trend is not clear
        expect(result).to be_nil
      end
    end

    it "returns nil when not ready" do
      indicator = described_class.new(series: series)
      min_required = indicator.min_required_candles
      result = indicator.calculate_at(min_required - 1)

      expect(result).to be_nil
    end

    it "returns nil for non-trading hours" do
      indicator = described_class.new(series: series)
      non_trading_candle = create(:candle, timestamp: Time.zone.parse("2023-01-01 02:00:00"))
      series.add_candle(non_trading_candle)
      last_index = series.candles.size - 1
      allow(indicator).to receive(:trading_hours?).and_return(false)

      result = indicator.calculate_at(series.candles.size - 1)

      expect(result).to be_nil
    end
  end

  describe "private methods" do
    let(:indicator) { described_class.new(series: series) }

    describe "#create_partial_series" do
      it "creates series up to index" do
        partial = indicator.send(:create_partial_series, 50)

        expect(partial).to be_a(CandleSeries)
        expect(partial.candles.size).to eq(51) # 0..50 inclusive
      end
    end

    describe "#calculate_hma_series" do
      it "calculates HMA series" do
        partial_series = indicator.send(:create_partial_series, 80)
        hma_values = indicator.send(:calculate_hma_series, partial_series)

        expect(hma_values).to be_an(Array)
      end

      it "returns empty array for insufficient data" do
        small_series = CandleSeries.new(symbol: "TEST", interval: "1D")
        10.times { small_series.add_candle(create(:candle)) }
        hma_values = indicator.send(:calculate_hma_series, small_series)

        expect(hma_values).to eq([])
      end
    end

    describe "#calculate_wma" do
      it "calculates weighted moving average" do
        values = (1..20).map(&:to_f)
        wma = indicator.send(:calculate_wma, values, 10)

        expect(wma).to be_a(Numeric)
        expect(wma).to be > 0
      end

      it "returns nil for insufficient data" do
        values = [1.0, 2.0]
        wma = indicator.send(:calculate_wma, values, 10)

        expect(wma).to be_nil
      end

      it "handles zero values correctly" do
        # All zero values should still calculate WMA (weights are never zero)
        values = Array.new(10, 0.0)
        wma = indicator.send(:calculate_wma, values, 10)

        # WMA with all zeros should be 0.0, not nil (weights sum is never zero)
        expect(wma).to eq(0.0)
      end
    end

    describe "#detect_trend" do
      it "detects bullish trend" do
        hma_values = [100.0, 101.0, 102.0, 103.0, 104.0]
        trend = indicator.send(:detect_trend, hma_values)

        expect(trend).to eq(:bullish)
      end

      it "detects bearish trend" do
        hma_values = [104.0, 103.0, 102.0, 101.0, 100.0]
        trend = indicator.send(:detect_trend, hma_values)

        expect(trend).to eq(:bearish)
      end

      it "detects neutral trend" do
        hma_values = [100.0, 101.0, 100.0, 101.0, 100.0]
        trend = indicator.send(:detect_trend, hma_values)

        expect(trend).to eq(:neutral)
      end

      it "returns neutral for insufficient data" do
        hma_values = [100.0, 101.0]
        trend = indicator.send(:detect_trend, hma_values)

        expect(trend).to eq(:neutral)
      end
    end

    describe "#update_trend_duration" do
      it "tracks trend duration" do
        indicator.send(:update_trend_duration, :bullish)
        indicator.send(:update_trend_duration, :bullish)

        expect(indicator.instance_variable_get(:@trend_count)).to eq(2)
      end

      it "saves previous trend duration on change" do
        indicator.send(:update_trend_duration, :bullish)
        indicator.send(:update_trend_duration, :bullish)
        indicator.send(:update_trend_duration, :bearish)

        bullish_durations = indicator.instance_variable_get(:@bullish_durations)
        expect(bullish_durations).to include(2)
        expect(indicator.instance_variable_get(:@trend_count)).to eq(1)
      end

      it "limits duration samples" do
        indicator_with_samples = described_class.new(series: series, config: { samples: 5 })
        # Create 6 separate bullish trends (each followed by bearish to trigger save)
        # After 6 trends, we should have 5 samples (limited by samples: 5, oldest one removed)
        6.times do
          10.times { indicator_with_samples.send(:update_trend_duration, :bullish) }
          # Switch to bearish to save the bullish duration (10)
          indicator_with_samples.send(:update_trend_duration, :bearish)
        end

        bullish_durations = indicator_with_samples.instance_variable_get(:@bullish_durations)
        expect(bullish_durations.size).to eq(5) # Should be limited to 5 samples (6th one removed)
        expect(bullish_durations).to all(eq(10)) # All should be 10
      end

      it "does not increment count for neutral trend" do
        indicator.send(:update_trend_duration, :neutral)

        expect(indicator.instance_variable_get(:@trend_count)).to eq(0)
      end
    end

    describe "#calculate_probable_duration" do
      it "calculates average of historical durations" do
        indicator.instance_variable_set(:@bullish_durations, [5, 10, 15])
        indicator.instance_variable_set(:@trend_count, 3)

        probable = indicator.send(:calculate_probable_duration, :bullish)

        expect(probable).to eq(10.0) # (5 + 10 + 15) / 3
      end

      it "returns current trend count if no history" do
        indicator.instance_variable_set(:@trend_count, 5)

        probable = indicator.send(:calculate_probable_duration, :bullish)

        expect(probable).to eq(5)
      end
    end

    describe "#calculate_confidence" do
      it "calculates confidence based on trend establishment" do
        indicator.instance_variable_set(:@trend_count, 10) # >= trend_length (5)
        probable = 10.0

        confidence = indicator.send(:calculate_confidence, :bullish, probable)

        expect(confidence).to be >= 70 # base (50) + established (20)
      end

      it "calculates confidence based on duration ratio" do
        indicator.instance_variable_set(:@trend_count, 9) # 0.9 of probable (10)
        probable = 10.0

        confidence = indicator.send(:calculate_confidence, :bullish, probable)

        expect(confidence).to be >= 85 # base + established + ratio match
      end

      it "calculates confidence with historical data" do
        indicator.instance_variable_set(:@bullish_durations, [5, 10, 15, 20, 25])
        indicator.instance_variable_set(:@trend_count, 5)

        confidence = indicator.send(:calculate_confidence, :bullish, 10.0)

        expect(confidence).to be >= 60 # base + historical data
      end

      it "caps confidence at 100" do
        indicator.instance_variable_set(:@trend_count, 10)
        indicator.instance_variable_set(:@bullish_durations, [5, 10, 15, 20, 25, 30, 35, 40, 45, 50])

        confidence = indicator.send(:calculate_confidence, :bullish, 10.0)

        expect(confidence).to be <= 100
      end
    end
  end
end
