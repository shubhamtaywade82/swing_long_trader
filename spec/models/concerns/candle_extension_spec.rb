# frozen_string_literal: true

require "rails_helper"

RSpec.describe CandleExtension, type: :concern do
  let(:instrument) { create(:instrument) }

  describe "#candles" do
    context "when caching is disabled" do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          data_freshness: { disable_ohlc_caching: true },
        )
        allow(instrument).to receive(:intraday_ohlc).and_return([])
      end

      it "fetches fresh candles" do
        instrument.candles(interval: "15")

        expect(instrument).to have_received(:intraday_ohlc).with(interval: "15")
      end
    end

    context "when caching is enabled" do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({})
        allow(instrument).to receive(:intraday_ohlc).and_return([])
      end

      it "caches candles" do
        instrument.candles(interval: "15")
        instrument.candles(interval: "15")

        # Should only call API once due to caching
        expect(instrument).to have_received(:intraday_ohlc).once
      end
    end
  end

  describe "#ohlc_stale?" do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return({})
    end

    context "when cache is fresh" do
      it "returns false" do
        instrument.instance_variable_set(:@last_ohlc_fetched, { "15" => 1.minute.ago })

        expect(instrument.ohlc_stale?("15")).to be false
      end
    end

    context "when cache is stale" do
      it "returns true" do
        instrument.instance_variable_set(:@last_ohlc_fetched, { "15" => 10.minutes.ago })

        expect(instrument.ohlc_stale?("15")).to be true
      end
    end
  end

  describe "#rsi" do
    let(:series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "15") }

    before do
      allow(instrument).to receive(:candles).and_return(series)
      allow(series).to receive(:rsi).and_return(65.0)
    end

    it "delegates to candle series" do
      result = instrument.rsi(14, interval: "15")

      expect(result).to eq(65.0)
      expect(series).to have_received(:rsi).with(14)
    end
  end

  describe "#macd" do
    let(:series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "15") }

    before do
      allow(instrument).to receive(:candles).and_return(series)
      allow(series).to receive(:macd).and_return([1.0, 0.5, 0.5])
    end

    it "returns formatted MACD result" do
      result = instrument.macd(12, 26, 9, interval: "15")

      expect(result).to have_key(:macd)
      expect(result).to have_key(:signal)
      expect(result).to have_key(:histogram)
    end
  end

  describe "#adx" do
    let(:series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "15") }

    before do
      allow(instrument).to receive(:candles).and_return(series)
      allow(series).to receive(:adx).and_return(25.0)
    end

    it "delegates to candle series" do
      result = instrument.adx(14, interval: "15")

      expect(result).to eq(25.0)
    end
  end

  describe "#obv" do
    let(:series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "15") }

    before do
      allow(instrument).to receive(:candles).and_return(series)
      allow(TechnicalAnalysis::Obv).to receive(:calculate).and_return([100.0])
    end

    it "calculates OBV" do
      result = instrument.obv(interval: "15")

      expect(result).to be_present
    end

    context "when calculation fails" do
      before do
        allow(TechnicalAnalysis::Obv).to receive(:calculate).and_raise(ArgumentError, "Error")
        allow(Rails.logger).to receive(:warn)
      end

      it "returns nil and logs warning" do
        result = instrument.obv(interval: "15")

        expect(result).to be_nil
        expect(Rails.logger).to have_received(:warn)
      end
    end

    context "when calculation fails with TypeError" do
      before do
        allow(TechnicalAnalysis::Obv).to receive(:calculate).and_raise(TypeError, "Type error")
        allow(Rails.logger).to receive(:warn)
      end

      it "returns nil and logs warning" do
        result = instrument.obv(interval: "15")

        expect(result).to be_nil
        expect(Rails.logger).to have_received(:warn)
      end
    end

    context "when calculation fails with NoMethodError" do
      before do
        allow(TechnicalAnalysis::Obv).to receive(:calculate).and_raise(NoMethodError, "Method error")
      end

      it "raises the error" do
        expect do
          instrument.obv(interval: "15")
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe "#supertrend_signal" do
    let(:series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "15") }

    before do
      allow(instrument).to receive(:candles).and_return(series)
      allow(series).to receive(:supertrend_signal).and_return(:bullish)
    end

    it "delegates to candle series" do
      result = instrument.supertrend_signal(interval: "15")

      expect(result).to eq(:bullish)
    end
  end

  describe "#liquidity_grab_up?" do
    let(:series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "15") }

    before do
      allow(instrument).to receive(:candles).and_return(series)
      allow(series).to receive(:liquidity_grab_up?).and_return(true)
    end

    it "delegates to candle series" do
      result = instrument.liquidity_grab_up?(interval: "15")

      expect(result).to be true
    end
  end

  describe "#liquidity_grab_down?" do
    let(:series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "15") }

    before do
      allow(instrument).to receive(:candles).and_return(series)
      allow(series).to receive(:liquidity_grab_down?).and_return(false)
    end

    it "delegates to candle series" do
      result = instrument.liquidity_grab_down?(interval: "15")

      expect(result).to be false
    end
  end

  describe "#bollinger_bands" do
    let(:series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "15") }

    before do
      allow(instrument).to receive(:candles).and_return(series)
      allow(series).to receive(:bollinger_bands).and_return({ upper: 110.0, middle: 100.0, lower: 90.0 })
    end

    it "delegates to candle series" do
      result = instrument.bollinger_bands(period: 20, interval: "15")

      expect(result).to have_key(:upper)
      expect(result).to have_key(:middle)
      expect(result).to have_key(:lower)
    end

    it "returns nil when candles are nil" do
      allow(instrument).to receive(:candles).and_return(nil)

      result = instrument.bollinger_bands(period: 20, interval: "15")

      expect(result).to be_nil
    end
  end

  describe "#donchian_channel" do
    let(:series) { CandleSeries.new(symbol: instrument.symbol_name, interval: "15") }

    before do
      allow(instrument).to receive(:candles).and_return(series)
      allow(TechnicalAnalysis::Dc).to receive(:calculate).and_return([{ upper: 110.0, lower: 90.0 }])
    end

    it "calculates Donchian channel" do
      result = instrument.donchian_channel(period: 20, interval: "15")

      expect(result).to be_present
    end

    it "returns nil when candles are nil" do
      allow(instrument).to receive(:candles).and_return(nil)

      result = instrument.donchian_channel(period: 20, interval: "15")

      expect(result).to be_nil
    end
  end

  describe "#candle_series" do
    before do
      allow(instrument).to receive(:candles).and_return(
        CandleSeries.new(symbol: instrument.symbol_name, interval: "15"),
      )
    end

    it "delegates to candles method" do
      result = instrument.candle_series(interval: "15")

      expect(result).to be_a(CandleSeries)
    end
  end

  describe "#fetch_fresh_candles" do
    before do
      allow(instrument).to receive(:intraday_ohlc).and_return([
                                                                { timestamp: Time.current.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1000 },
                                                              ])
    end

    it "fetches and loads candles into series" do
      series = instrument.send(:fetch_fresh_candles, "15")

      expect(series).to be_a(CandleSeries)
      expect(series.interval).to eq("15")
    end

    it "returns nil when API returns blank data" do
      allow(instrument).to receive(:intraday_ohlc).and_return([])

      result = instrument.send(:fetch_fresh_candles, "15")

      expect(result).to be_nil
    end
  end

  describe "#ohlc_stale?" do
    it "uses configured cache duration" do
      allow(AlgoConfig).to receive(:fetch).and_return(
        data_freshness: { ohlc_cache_duration_minutes: 10 },
      )

      instrument.instance_variable_set(:@last_ohlc_fetched, { "15" => 5.minutes.ago })
      expect(instrument.ohlc_stale?("15")).to be false

      instrument.instance_variable_set(:@last_ohlc_fetched, { "15" => 15.minutes.ago })
      expect(instrument.ohlc_stale?("15")).to be true
    end

    it "uses default cache duration when not configured" do
      allow(AlgoConfig).to receive(:fetch).and_return({})

      instrument.instance_variable_set(:@last_ohlc_fetched, { "15" => 3.minutes.ago })
      expect(instrument.ohlc_stale?("15")).to be false

      instrument.instance_variable_set(:@last_ohlc_fetched, { "15" => 10.minutes.ago })
      expect(instrument.ohlc_stale?("15")).to be true
    end

    it "updates last_fetched timestamp" do
      allow(AlgoConfig).to receive(:fetch).and_return({})

      instrument.ohlc_stale?("15")

      expect(instrument.instance_variable_get(:@last_ohlc_fetched)["15"]).to be_present
    end
  end
end
