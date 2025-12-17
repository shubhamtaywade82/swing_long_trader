# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Candle Verification Scenarios", type: :service do
  # Tests based on CANDLE_INGESTION_GUIDE.md Section 5: Verification & Monitoring

  let(:instrument) { create(:instrument, symbol_name: "TEST", security_id: "12345", segment: "equity") }
  let(:instrument2) { create(:instrument, symbol_name: "TEST2", security_id: "12346", segment: "equity") }

  describe "Minimum Candle Requirements Verification" do
    context "when verifying 365 daily candles requirement" do
      it "identifies instruments with insufficient daily candles" do
        # Create only 100 daily candles (insufficient)
        (0..99).each do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day)
        end

        insufficient = []
        Instrument.where(segment: %w[equity index]).find_each do |inst|
          daily_count = CandleSeriesRecord.daily.where(instrument: inst).count
          insufficient << { symbol: inst.symbol_name, daily: daily_count } if daily_count < 365
        end

        expect(insufficient).not_to be_empty
        expect(insufficient.first[:daily]).to eq(100)
      end

      it "identifies instruments with sufficient daily candles" do
        # Create 365 daily candles (sufficient)
        (0..364).each do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day)
        end

        insufficient = []
        Instrument.where(segment: %w[equity index]).find_each do |inst|
          daily_count = CandleSeriesRecord.daily.where(instrument: inst).count
          insufficient << { symbol: inst.symbol_name, daily: daily_count } if daily_count < 365
        end

        # Should not include instrument with 365 candles
        expect(insufficient.select { |i| i[:symbol] == "TEST" }).to be_empty
      end
    end

    context "when verifying 52 weekly candles requirement" do
      it "identifies instruments with insufficient weekly candles" do
        # Create only 20 weekly candles (insufficient)
        (0..19).each do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :weekly,
                 timestamp: i.weeks.ago.beginning_of_week)
        end

        insufficient = []
        Instrument.where(segment: %w[equity index]).find_each do |inst|
          weekly_count = CandleSeriesRecord.weekly.where(instrument: inst).count
          insufficient << { symbol: inst.symbol_name, weekly: weekly_count } if weekly_count < 52
        end

        expect(insufficient).not_to be_empty
        expect(insufficient.first[:weekly]).to eq(20)
      end
    end

    context "when verifying 365 hourly candles requirement" do
      it "identifies instruments with insufficient hourly candles" do
        # Create only 100 hourly candles (insufficient)
        (0..99).each do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :hourly,
                 timestamp: i.hours.ago)
        end

        insufficient = []
        Instrument.where(segment: %w[equity index]).find_each do |inst|
          hourly_count = CandleSeriesRecord.hourly.where(instrument: inst).count
          insufficient << { symbol: inst.symbol_name, hourly: hourly_count } if hourly_count < 365
        end

        expect(insufficient).not_to be_empty
        expect(insufficient.first[:hourly]).to eq(100)
      end
    end

    context "when checking multiple timeframes" do
      it "reports all insufficient timeframes for an instrument" do
        # Create insufficient candles for all timeframes
        (0..100).each do |i|
          create(:candle_series_record, instrument: instrument, timeframe: :daily, timestamp: i.days.ago.beginning_of_day)
        end
        (0..20).each do |i|
          create(:candle_series_record, instrument: instrument, timeframe: :weekly, timestamp: i.weeks.ago.beginning_of_week)
        end
        (0..100).each do |i|
          create(:candle_series_record, instrument: instrument, timeframe: :hourly, timestamp: i.hours.ago)
        end

        insufficient = []
        Instrument.where(segment: %w[equity index]).find_each do |inst|
          daily_count = CandleSeriesRecord.daily.where(instrument: inst).count
          weekly_count = CandleSeriesRecord.weekly.where(instrument: inst).count
          hourly_count = CandleSeriesRecord.hourly.where(instrument: inst).count

          if daily_count < 365 || weekly_count < 52 || hourly_count < 365
            insufficient << {
              symbol: inst.symbol_name,
              daily: daily_count,
              weekly: weekly_count,
              hourly: hourly_count,
            }
          end
        end

        test_item = insufficient.find { |i| i[:symbol] == "TEST" }
        expect(test_item).to be_present
        expect(test_item[:daily]).to be < 365
        expect(test_item[:weekly]).to be < 52
        expect(test_item[:hourly]).to be < 365
      end
    end
  end

  describe "Candle Freshness Verification" do
    context "when checking daily candle freshness" do
      it "reports freshness percentage correctly" do
        # Create fresh candle
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 1.day.ago.beginning_of_day)

        # Create stale candle
        create(:candle_series_record,
               instrument: instrument2,
               timeframe: :daily,
               timestamp: 10.days.ago.beginning_of_day)

        daily_freshness = Candles::FreshnessChecker.check_freshness(timeframe: :daily)

        expect(daily_freshness).to have_key(:freshness_percentage)
        expect(daily_freshness[:freshness_percentage]).to be_a(Numeric)
      end
    end

    context "when checking weekly candle freshness" do
      it "reports freshness percentage correctly" do
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :weekly,
               timestamp: 1.week.ago.beginning_of_week)

        weekly_freshness = Candles::FreshnessChecker.check_freshness(timeframe: :weekly)

        expect(weekly_freshness).to have_key(:freshness_percentage)
        expect(weekly_freshness[:timeframe]).to eq(:weekly)
      end
    end

    context "when auto-ingesting stale candles" do
      before do
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 10.days.ago.beginning_of_day)
      end

      it "triggers ingestion when stale" do
        allow(Candles::DailyIngestor).to receive(:call).and_return(
          { success: 1, processed: 1, total_candles: 10 },
        )

        Candles::FreshnessChecker.ensure_fresh(timeframe: :daily, auto_ingest: true)

        expect(Candles::DailyIngestor).to have_received(:call)
      end
    end
  end

  describe "Date Range Verification" do
    context "when checking candle date ranges" do
      it "reports first and last candle dates correctly" do
        first_date = 365.days.ago.to_date
        last_date = 1.day.ago.to_date

        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: first_date.beginning_of_day)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: last_date.beginning_of_day)

        candles = CandleSeriesRecord.daily.where(instrument: instrument).order(:timestamp)

        expect(candles.first.timestamp.to_date).to eq(first_date)
        expect(candles.last.timestamp.to_date).to eq(last_date)
        expect(candles.count).to eq(2)
      end
    end
  end

  describe "Instruments Without Candles" do
    context "when finding instruments without candles" do
      it "identifies instruments with no daily candles" do
        # instrument has no candles, instrument2 has candles
        create(:candle_series_record,
               instrument: instrument2,
               timeframe: :daily,
               timestamp: 1.day.ago.beginning_of_day)

        instruments_without_candles = Instrument
                                      .where(segment: %w[equity index])
                                      .where.missing(:candle_series_records)
                                      .distinct

        expect(instruments_without_candles).to include(instrument)
        expect(instruments_without_candles).not_to include(instrument2)
      end
    end
  end

  describe "Gap Detection" do
    context "when detecting gaps in candle data" do
      it "identifies missing dates in candle sequence" do
        # Create candles with gaps
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 10.days.ago.beginning_of_day)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 5.days.ago.beginning_of_day)
        # Gap: missing candles for days 9, 8, 7, 6

        candles = CandleSeriesRecord.daily.where(instrument: instrument).order(:timestamp)
        dates = candles.pluck(:timestamp).map(&:to_date)
        expected_dates = (dates.min..dates.max).select { |d| (1..5).include?(d.wday) } # Weekdays only
        missing_dates = expected_dates - dates

        expect(missing_dates).not_to be_empty
        expect(missing_dates.size).to be >= 4 # At least 4 missing weekdays
      end
    end
  end

  describe "Candle Count Verification" do
    context "when checking candle counts per instrument" do
      it "reports correct candle counts" do
        # Clear existing candles for this instrument first
        CandleSeriesRecord.where(instrument: instrument).delete_all

        # Create 100 daily candles (smaller number for faster test)
        (0..99).each do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day)
        end

        daily_count = CandleSeriesRecord.daily.where(instrument: instrument).count
        expect(daily_count).to eq(100)

        # Check via group count
        counts_by_instrument = CandleSeriesRecord.daily.group(:instrument_id).count
        expect(counts_by_instrument[instrument.id]).to eq(100)
      end
    end
  end

  describe "Latest Candle Verification" do
    context "when checking latest candle dates" do
      it "finds latest daily candle correctly" do
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 5.days.ago.beginning_of_day)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 1.day.ago.beginning_of_day)

        latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: :daily)

        expect(latest).to be_present
        expect(latest.timestamp.to_date).to eq(1.day.ago.to_date)
      end

      it "finds latest weekly candle correctly" do
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :weekly,
               timestamp: 3.weeks.ago.beginning_of_week)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :weekly,
               timestamp: 1.week.ago.beginning_of_week)

        latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: :weekly)

        expect(latest).to be_present
        expect(latest.timestamp.to_date).to eq(1.week.ago.beginning_of_week.to_date)
      end
    end
  end
end
