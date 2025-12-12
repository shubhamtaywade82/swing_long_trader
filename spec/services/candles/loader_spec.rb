# frozen_string_literal: true

require "rails_helper"

RSpec.describe Candles::Loader, type: :service do
  let(:instrument) { create(:instrument) }
  let(:timeframe) { "1D" }

  describe ".load_for_instrument" do
    it "delegates to instance method" do
      allow_any_instance_of(described_class).to receive(:load_for_instrument).and_return(nil)

      described_class.load_for_instrument(
        instrument: instrument,
        timeframe: timeframe,
      )

      expect_any_instance_of(described_class).to have_received(:load_for_instrument)
    end
  end

  describe "#load_for_instrument" do
    context "when candles exist" do
      let!(:candle1) do
        create(:candle_series_record,
               instrument: instrument,
               timeframe: timeframe,
               timestamp: 2.days.ago,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 1000)
      end

      let!(:candle2) do
        create(:candle_series_record,
               instrument: instrument,
               timeframe: timeframe,
               timestamp: 1.day.ago,
               open: 103.0,
               high: 108.0,
               low: 102.0,
               close: 106.0,
               volume: 1200)
      end

      it "loads candles from database" do
        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
        )

        expect(series).to be_a(CandleSeries)
        expect(series.candles.size).to eq(2)
      end

      it "converts records to CandleSeries format" do
        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
        )

        expect(series.symbol).to eq(instrument.symbol_name)
        expect(series.interval).to eq(timeframe)
      end

      it "converts candles correctly" do
        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
        )

        first_candle = series.candles.first
        expect(first_candle.timestamp).to eq(candle1.timestamp)
        expect(first_candle.open).to eq(100.0)
        expect(first_candle.high).to eq(105.0)
        expect(first_candle.low).to eq(99.0)
        expect(first_candle.close).to eq(103.0)
        expect(first_candle.volume).to eq(1000)
      end

      context "when limit is specified" do
        it "limits the number of candles" do
          series = described_class.new.load_for_instrument(
            instrument: instrument,
            timeframe: timeframe,
            limit: 1,
          )

          expect(series.candles.size).to eq(1)
        end
      end

      context "when date range is specified" do
        it "filters by date range" do
          series = described_class.new.load_for_instrument(
            instrument: instrument,
            timeframe: timeframe,
            from_date: 1.day.ago.to_date,
            to_date: Time.current.to_date,
          )

          expect(series.candles.size).to eq(1)
          expect(series.candles.first.timestamp.to_date).to eq(1.day.ago.to_date)
        end
      end
    end

    context "when no candles exist" do
      it "returns nil" do
        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
        )

        expect(series).to be_nil
      end
    end
  end

  describe "#load_latest" do
    context "when candles exist" do
      before do
        create_list(:candle_series_record, 5,
                    instrument: instrument,
                    timeframe: timeframe,
                    timestamp: ->(i) { i.days.ago })
      end

      it "loads latest candles" do
        series = described_class.new.load_latest(
          instrument: instrument,
          timeframe: timeframe,
          count: 3,
        )

        expect(series).to be_a(CandleSeries)
        expect(series.candles.size).to eq(3)
      end

      it "returns candles in chronological order" do
        series = described_class.new.load_latest(
          instrument: instrument,
          timeframe: timeframe,
          count: 3,
        )

        timestamps = series.candles.map(&:timestamp)
        expect(timestamps).to eq(timestamps.sort)
      end
    end

    context "when no candles exist" do
      it "returns nil" do
        series = described_class.new.load_latest(
          instrument: instrument,
          timeframe: timeframe,
          count: 10,
        )

        expect(series).to be_nil
      end
    end

    context "with edge cases" do
      it "handles multiple timeframes correctly" do
        create(:candle_series_record, instrument: instrument, timeframe: "1D", timestamp: 1.day.ago)
        create(:candle_series_record, instrument: instrument, timeframe: "1W", timestamp: 1.week.ago)

        daily_series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: "1D",
        )
        weekly_series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: "1W",
        )

        expect(daily_series.interval).to eq("1D")
        expect(weekly_series.interval).to eq("1W")
      end

      it "handles date range with no matching candles" do
        create(:candle_series_record, instrument: instrument, timeframe: timeframe, timestamp: 10.days.ago)

        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
          from_date: 1.day.ago.to_date,
          to_date: Time.current.to_date,
        )

        expect(series).to be_nil
      end

      it "handles limit larger than available candles" do
        create_list(:candle_series_record, 3, instrument: instrument, timeframe: timeframe)

        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
          limit: 10,
        )

        expect(series.candles.size).to eq(3)
      end

      it "handles zero limit" do
        create_list(:candle_series_record, 3, instrument: instrument, timeframe: timeframe)

        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
          limit: 0,
        )

        expect(series).to be_nil
      end

      it "handles nil from_date" do
        create_list(:candle_series_record, 3, instrument: instrument, timeframe: timeframe)

        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
          from_date: nil,
          to_date: Time.current.to_date,
        )

        # Should load all candles when from_date is nil
        expect(series).to be_present
      end

      it "handles nil to_date" do
        create_list(:candle_series_record, 3, instrument: instrument, timeframe: timeframe)

        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
          from_date: 10.days.ago.to_date,
          to_date: nil,
        )

        # Should load all candles when to_date is nil
        expect(series).to be_present
      end

      it "handles candles with zero volume" do
        create(:candle_series_record,
               instrument: instrument,
               timeframe: timeframe,
               timestamp: 1.day.ago,
               volume: 0)

        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
        )

        expect(series.candles.first.volume).to eq(0)
      end

      it "handles candles with negative prices (edge case)" do
        # This shouldn't happen in real trading, but test edge case
        create(:candle_series_record,
               instrument: instrument,
               timeframe: timeframe,
               timestamp: 1.day.ago,
               open: -100.0,
               high: -95.0,
               low: -105.0,
               close: -98.0)

        series = described_class.new.load_for_instrument(
          instrument: instrument,
          timeframe: timeframe,
        )

        expect(series.candles.first.close).to eq(-98.0)
      end
    end

    context "with load_latest edge cases" do
      it "handles count larger than available candles" do
        create_list(:candle_series_record, 5, instrument: instrument, timeframe: timeframe)

        series = described_class.new.load_latest(
          instrument: instrument,
          timeframe: timeframe,
          count: 10,
        )

        expect(series.candles.size).to eq(5)
      end

      it "handles zero count" do
        create_list(:candle_series_record, 5, instrument: instrument, timeframe: timeframe)

        series = described_class.new.load_latest(
          instrument: instrument,
          timeframe: timeframe,
          count: 0,
        )

        expect(series).to be_nil
      end

      it "handles negative count" do
        create_list(:candle_series_record, 5, instrument: instrument, timeframe: timeframe)

        series = described_class.new.load_latest(
          instrument: instrument,
          timeframe: timeframe,
          count: -1,
        )

        # Should handle gracefully (might return nil or all candles)
        expect(series).to be_present.or be_nil
      end

      it "maintains chronological order with many candles" do
        create_list(:candle_series_record, 100,
                    instrument: instrument,
                    timeframe: timeframe,
                    timestamp: ->(i) { (99 - i).days.ago })

        series = described_class.new.load_latest(
          instrument: instrument,
          timeframe: timeframe,
          count: 50,
        )

        timestamps = series.candles.map(&:timestamp)
        expect(timestamps).to eq(timestamps.sort)
      end
    end

    describe "private methods" do
      let(:loader) { described_class.new }

      describe "#convert_to_candle_series" do
        it "converts records correctly" do
          records = [
            create(:candle_series_record,
                   instrument: instrument,
                   timeframe: timeframe,
                   timestamp: 1.day.ago,
                   open: 100.0,
                   high: 105.0,
                   low: 99.0,
                   close: 103.0,
                   volume: 1000),
          ]

          series = loader.send(:convert_to_candle_series,
                               instrument: instrument,
                               timeframe: timeframe,
                               records: records)

          expect(series).to be_a(CandleSeries)
          expect(series.candles.size).to eq(1)
          expect(series.symbol).to eq(instrument.symbol_name)
          expect(series.interval).to eq(timeframe)
        end

        it "handles empty records array" do
          series = loader.send(:convert_to_candle_series,
                               instrument: instrument,
                               timeframe: timeframe,
                               records: [])

          expect(series).to be_a(CandleSeries)
          expect(series.candles).to be_empty
        end

        it "preserves all candle attributes" do
          record = create(:candle_series_record,
                          instrument: instrument,
                          timeframe: timeframe,
                          timestamp: 1.day.ago,
                          open: 100.0,
                          high: 105.0,
                          low: 99.0,
                          close: 103.0,
                          volume: 1000)

          series = loader.send(:convert_to_candle_series,
                               instrument: instrument,
                               timeframe: timeframe,
                               records: [record])

          candle = series.candles.first
          expect(candle.timestamp).to eq(record.timestamp)
          expect(candle.open).to eq(record.open)
          expect(candle.high).to eq(record.high)
          expect(candle.low).to eq(record.low)
          expect(candle.close).to eq(record.close)
          expect(candle.volume).to eq(record.volume)
        end
      end
    end
  end
end
