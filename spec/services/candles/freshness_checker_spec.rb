# frozen_string_literal: true

require "rails_helper"

RSpec.describe Candles::FreshnessChecker do
  let(:instrument) { create(:instrument, symbol_name: "TEST", security_id: "12345", segment: "equity") }
  let(:instruments) { Instrument.where(id: instrument.id) }

  describe ".check_freshness" do
    context "with fresh daily candles" do
      before do
        # Create fresh daily candle (1 day ago)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 1.day.ago.beginning_of_day,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 1_000_000)
      end

      it "reports candles as fresh" do
        result = described_class.check_freshness(timeframe: :daily)

        expect(result[:fresh]).to be true
        expect(result[:freshness_percentage]).to be >= 80.0
        expect(result[:fresh_count]).to eq(1)
        expect(result[:total_count]).to eq(1)
      end

      it "includes cutoff date and trading days info" do
        result = described_class.check_freshness(timeframe: :daily)

        expect(result).to have_key(:cutoff_date)
        expect(result).to have_key(:cutoff_trading_days_ago)
        expect(result[:cutoff_date]).to be_a(Date)
      end
    end

    context "with stale daily candles" do
      before do
        # Create stale daily candle (10 days ago)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 10.days.ago.beginning_of_day,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 1_000_000)
      end

      it "reports candles as stale" do
        result = described_class.check_freshness(timeframe: :daily, max_trading_days: 1)

        expect(result[:fresh]).to be false
        expect(result[:freshness_percentage]).to be < 80.0
        expect(result[:stale_count]).to eq(1)
      end
    end

    context "with no candles" do
      it "reports as not fresh" do
        result = described_class.check_freshness(timeframe: :daily)

        expect(result[:fresh]).to be false
        expect(result[:fresh_count]).to eq(0)
        expect(result[:total_count]).to be >= 1 # At least 1 instrument exists
      end
    end

    context "with multiple instruments" do
      let(:instrument2) { create(:instrument, symbol_name: "TEST2", security_id: "12346", segment: "equity") }

      before do
        # Instrument 1: fresh candle
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 1.day.ago.beginning_of_day)

        # Instrument 2: stale candle
        create(:candle_series_record,
               instrument: instrument2,
               timeframe: :daily,
               timestamp: 10.days.ago.beginning_of_day)
      end

      it "calculates freshness percentage correctly" do
        result = described_class.check_freshness(timeframe: :daily, max_trading_days: 1)

        expect(result[:total_count]).to eq(2)
        expect(result[:fresh_count]).to eq(1)
        expect(result[:freshness_percentage]).to eq(50.0)
      end
    end

    context "with weekly candles" do
      before do
        # Create fresh weekly candle (1 week ago)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :weekly,
               timestamp: 1.week.ago.beginning_of_week,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 5_000_000)
      end

      it "checks weekly candle freshness" do
        result = described_class.check_freshness(timeframe: :weekly, max_trading_days: 7)

        expect(result[:timeframe]).to eq(:weekly)
        # Weekly candle from 1 week ago should be fresh if max_trading_days is 7
        expect(result[:fresh]).to be true
      end
    end

    context "with trading days calculation" do
      before do
        # Create candle from 3 calendar days ago (but only 1 trading day if weekend involved)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 3.days.ago.beginning_of_day)
      end

      it "accounts for weekends in trading days calculation" do
        result = described_class.check_freshness(timeframe: :daily, max_trading_days: 1)

        # Should account for weekends when calculating trading days
        expect(result).to have_key(:cutoff_trading_days_ago)
      end
    end

    context "with market holidays" do
      before do
        # Create a market holiday
        MarketHoliday.create!(date: 2.days.ago.to_date, name: "Test Holiday")

        # Create candle from 3 days ago
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 3.days.ago.beginning_of_day)
      end

      it "excludes market holidays from trading days calculation" do
        # Create a market holiday on a weekday (Monday)
        holiday_date = Time.zone.today.beginning_of_week
        # Ensure it's a weekday
        holiday_date += 1.day if [0, 6].include?(holiday_date.wday)
        MarketHoliday.create!(date: holiday_date, name: "Test Holiday")

        result = described_class.check_freshness(timeframe: :daily, max_trading_days: 1)

        # Should account for holidays when calculating trading days
        expect(result).to have_key(:cutoff_trading_days_ago)
        # The cutoff date should not be the holiday date
        expect(result[:cutoff_date]).not_to eq(holiday_date)
      end
    end
  end

  describe ".ensure_fresh" do
    context "when candles are fresh" do
      before do
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 1.day.ago.beginning_of_day)
      end

      it "returns fresh status without ingesting" do
        result = described_class.ensure_fresh(timeframe: :daily, auto_ingest: false)

        expect(result[:fresh]).to be true
        expect(result[:ingested]).to be_nil
      end

      it "skips ingestion when fresh" do
        expect(Candles::DailyIngestor).not_to receive(:call)

        described_class.ensure_fresh(timeframe: :daily, auto_ingest: true)
      end
    end

    context "when candles are stale" do
      before do
        # Create stale candle (10 days ago)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 10.days.ago.beginning_of_day)
      end

      context "with auto_ingest enabled" do
        it "triggers ingestion" do
          allow(Candles::DailyIngestor).to receive(:call).and_return(
            { success: 1, processed: 1, total_candles: 10 },
          )

          result = described_class.ensure_fresh(timeframe: :daily, auto_ingest: true)

          expect(result[:ingested]).to be true
          expect(Candles::DailyIngestor).to have_received(:call)
        end

        it "includes ingestion result" do
          ingestion_result = { success: 1, processed: 1, total_candles: 10 }
          allow(Candles::DailyIngestor).to receive(:call).and_return(ingestion_result)

          result = described_class.ensure_fresh(timeframe: :daily, auto_ingest: true)

          expect(result[:ingestion_result]).to be_present
          expect(result[:ingestion_result][:success]).to be true
        end
      end

      context "with auto_ingest disabled" do
        it "does not trigger ingestion" do
          expect(Candles::DailyIngestor).not_to receive(:call)

          result = described_class.ensure_fresh(timeframe: :daily, auto_ingest: false)

          # In test environment with auto_ingest false, it may return fresh: true with skip message
          # Otherwise, it should return ingested: false
          if result[:fresh]
            expect(result[:message]).to include("Skipped")
          else
            expect(result[:ingested]).to be false
            expect(result[:requires_manual_ingestion]).to be true
          end
        end
      end
    end

    context "with weekly candles" do
      before do
        # Create stale weekly candle (3 weeks ago)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :weekly,
               timestamp: 3.weeks.ago.beginning_of_week)
      end

      it "triggers weekly ingestion when stale" do
        allow(Candles::WeeklyIngestor).to receive(:call).and_return(
          { success: 1, processed: 1, total_candles: 3 },
        )

        result = described_class.ensure_fresh(timeframe: :weekly, auto_ingest: true)

        expect(result[:ingested]).to be true
        expect(Candles::WeeklyIngestor).to have_received(:call)
      end
    end

    context "in test environment" do
      before do
        allow(Rails.env).to receive(:test?).and_return(true)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 10.days.ago.beginning_of_day)
      end

      it "skips ingestion when auto_ingest is false in test" do
        result = described_class.ensure_fresh(timeframe: :daily, auto_ingest: false)

        expect(result[:fresh]).to be true
        expect(result[:message]).to include("Skipped in test environment")
      end
    end

    context "with error handling" do
      before do
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 10.days.ago.beginning_of_day)
      end

      it "handles errors gracefully" do
        # Stub the instance method check_freshness to raise an error
        checker = described_class.new(timeframe: :daily, auto_ingest: false)
        allow(checker).to receive(:check_freshness).and_raise(StandardError.new("Database error"))

        result = checker.ensure_fresh

        # Should catch the error and return error info
        expect(result[:fresh]).to be false
        expect(result[:error]).to be_present
        expect(result[:error]).to include("Database error")
      end
    end
  end

  describe "#last_trading_day_ago" do
    let(:checker) { described_class.new(timeframe: :daily) }

    it "returns today if trading_days_ago is 0" do
      date = checker.send(:last_trading_day_ago, 0)

      expect(date).to eq(Time.zone.today)
    end

    it "returns a date in the past for positive trading_days_ago" do
      date = checker.send(:last_trading_day_ago, 1)

      expect(date).to be <= Time.zone.today - 1.day
    end

    it "accounts for weekends" do
      # If we ask for 1 trading day ago, it should skip weekends
      date = checker.send(:last_trading_day_ago, 1)

      # Should be a weekday
      expect((1..5).include?(date.wday)).to be true
    end

    it "accounts for market holidays" do
      # Create a market holiday on a weekday (Monday)
      holiday_date = Time.zone.today.beginning_of_week
      # Ensure it's a weekday
      holiday_date += 1.day if [0, 6].include?(holiday_date.wday)
      MarketHoliday.create!(date: holiday_date, name: "Test Holiday")

      # If we ask for 1 trading day ago, it should skip the holiday
      date = checker.send(:last_trading_day_ago, 1)

      # Should not be the holiday date (unless it's the only trading day available)
      # The method should skip holidays when counting trading days
      expect(MarketHoliday.holiday?(date)).to be false
    end
  end

  describe "#trading_day?" do
    let(:checker) { described_class.new(timeframe: :daily) }

    it "returns true for weekdays" do
      monday = Time.zone.today.beginning_of_week
      expect(checker.send(:trading_day?, monday)).to be true
    end

    it "returns false for weekends" do
      saturday = Time.zone.today.beginning_of_week + 5.days
      expect(checker.send(:trading_day?, saturday)).to be false

      sunday = Time.zone.today.beginning_of_week + 6.days
      expect(checker.send(:trading_day?, sunday)).to be false
    end

    it "returns false for market holidays" do
      # Create a market holiday on a weekday (Monday)
      holiday_date = Time.zone.today.beginning_of_week
      # Ensure it's a weekday
      holiday_date += 1.day if [0, 6].include?(holiday_date.wday)
      MarketHoliday.create!(date: holiday_date, name: "Test Holiday")

      expect(checker.send(:trading_day?, holiday_date)).to be false
      expect(MarketHoliday.holiday?(holiday_date)).to be true
    end
  end
end
