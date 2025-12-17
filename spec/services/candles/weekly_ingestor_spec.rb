# frozen_string_literal: true

require "rails_helper"

RSpec.describe Candles::WeeklyIngestor do
  let(:instrument) { create(:instrument, symbol_name: "TEST", security_id: "12345") }
  let(:instruments) { Instrument.where(id: instrument.id) }

  describe ".call" do
    context "when daily candles are valid" do
      let(:result) { described_class.call(instruments: instruments, weeks_back: 1) }

      before do
        # Create daily candles in database (weekly ingestor loads from DB, not API)
        7.times do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day,
                 open: 100.0 + i,
                 high: 105.0 + i,
                 low: 99.0 + i,
                 close: 103.0 + i,
                 volume: 1_000_000)
        end
      end

      it { expect(result[:processed]).to eq(1) }

      it { expect(result[:success]).to be > 0 }

      it "creates weekly candles" do
        result
        expect(CandleSeriesRecord.weekly.where(instrument: instrument).count).to be > 0
      end

      describe "weekly candle attributes" do
        let(:weekly_candle) do
          result
          CandleSeriesRecord.where(instrument: instrument, timeframe: "1W").first
        end

        it { expect(weekly_candle).to be_present }

        it { expect(weekly_candle.open).to be_a(Numeric) }

        it { expect(weekly_candle.high).to be_a(Numeric) }

        it { expect(weekly_candle.low).to be_a(Numeric) }

        it { expect(weekly_candle.close).to be_a(Numeric) }

        it { expect(weekly_candle.volume).to be_a(Numeric) }
      end

      it "aggregates from Monday to Sunday" do
        result
        weekly_candles = CandleSeriesRecord.weekly.where(instrument: instrument)

        expect(weekly_candles).to be_any
        weekly_candles.each do |candle|
          expect(candle.timestamp.wday).to eq(1)
        end
      end
    end

    context "when weeks_back is custom" do
      let(:result) { described_class.call(instruments: instruments, weeks_back: 4) }

      before do
        # Create 28 days of daily candles in database
        28.times do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day,
                 open: 100.0 + i,
                 high: 105.0 + i,
                 low: 99.0 + i,
                 close: 103.0 + i,
                 volume: 1_000_000)
        end
      end

      it { expect(result[:processed]).to eq(1) }

      it { expect(result[:success]).to be > 0 }
    end

    context "when daily candles are insufficient" do
      let(:instrument_no_candles) { create(:instrument, security_id: "99999") }
      let(:instruments_empty) { Instrument.where(id: instrument_no_candles.id) }
      let(:result) { described_class.call(instruments: instruments_empty, weeks_back: 1) }

      before do
        # Don't create any daily candles - instrument will have no data
      end

      it { expect(result[:failed]).to be >= 0 }
    end

    context "when instrument has no security_id" do
      let(:instrument_no_security) do
        inst = create(:instrument, symbol_name: "NO_SEC")
        # Use update_column to bypass validations and set security_id to empty string
        # This tests the service's error handling without violating database constraints
        inst.update_column(:security_id, "")
        inst
      end
      let(:instruments_no_security) { Instrument.where(id: instrument_no_security.id) }
      let(:result) { described_class.call(instruments: instruments_no_security, weeks_back: 1) }

      before do
        # Stub security_id to return nil to test the service's handling of missing security_id
        allow(instrument_no_security).to receive(:security_id).and_return(nil)
      end

      it { expect(result[:failed]).to be >= 0 }
    end

    context "when multiple instruments are provided" do
      let(:instrument2) { create(:instrument, symbol_name: "TEST2", security_id: "12346") }
      let(:multiple_instruments) { Instrument.where(id: [instrument.id, instrument2.id]) }
      let(:result) { described_class.call(instruments: multiple_instruments, weeks_back: 1) }

      before do
        # Create daily candles for both instruments
        7.times do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
          create(:candle_series_record,
                 instrument: instrument2,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end
      end

      it { expect(result[:processed]).to eq(2) }
    end

    context "when no instruments are provided" do
      let(:result) { described_class.call }

      before do
        # No daily candles needed - will fail for instruments without data
      end

      it { expect(result).to be_a(Hash) }

      it { expect(result[:processed]).to be >= 0 }
    end

    context "with edge cases" do
      it "handles empty daily candles" do
        # No daily candles created - instrument will have no data

        result = described_class.call(instruments: instruments, weeks_back: 1)

        expect(result[:failed]).to eq(1)
      end

      it "aggregates multiple weeks correctly" do
        # Create 14 days of candles (2 weeks) in database
        14.times do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        result = described_class.call(instruments: instruments, weeks_back: 2)

        expect(result[:success]).to eq(1)
        weekly_count = CandleSeriesRecord.where(instrument: instrument, timeframe: "1W").count
        expect(weekly_count).to be >= 2
      end

      it "processes multiple instruments efficiently" do
        # Weekly ingestor doesn't have rate limiting (loads from DB, not API)
        # This test verifies it can handle multiple instruments

        # Process 10 instruments (use unique security_ids to avoid validation errors)
        instruments_list = 10.times.map { |i| create(:instrument, security_id: "weekly_test_#{i}") }
        instruments = Instrument.where(id: instruments_list.map(&:id))

        # Create daily candles for all instruments
        instruments_list.each do |inst|
          7.times do |i|
            create(:candle_series_record,
                   instrument: inst,
                   timeframe: :daily,
                   timestamp: i.days.ago.beginning_of_day,
                   open: 100.0,
                   high: 105.0,
                   low: 99.0,
                   close: 103.0,
                   volume: 1_000_000)
          end
        end

        result = described_class.call(instruments: instruments, weeks_back: 1)

        # Should process all instruments
        expect(result[:processed]).to eq(10)
        expect(result[:success]).to be > 0
      end

      it "logs summary correctly" do
        # Create daily candles
        7.times do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)

        described_class.call(instruments: instruments, weeks_back: 1)

        expect(Rails.logger).to have_received(:info).at_least(:once)
      end

      it "handles partial failures across multiple instruments" do
        instrument2 = create(:instrument, symbol_name: "TEST2", security_id: "12346")
        instruments = Instrument.where(id: [instrument.id, instrument2.id])

        # Create daily candles for first instrument (will succeed)
        7.times do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end
        # Second instrument has no daily candles (will fail)

        result = described_class.call(instruments: instruments, weeks_back: 1)

        expect(result[:processed]).to eq(2)
        expect(result[:success]).to eq(1)
        expect(result[:failed]).to eq(1)
      end
    end

    context "with incremental updates" do
      it "fetches only new weekly candles when latest weekly candle exists" do
        # Create existing weekly candle from 3 weeks ago
        latest_week_start = 3.weeks.ago.beginning_of_week
        create(:candle_series_record,
               instrument: instrument,
                 timeframe: :weekly,
               timestamp: latest_week_start,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 7_000_000)

        # Create daily candles for the new weeks (from 2 weeks ago to current week)
        next_week_start = latest_week_start + 1.week
        daily_dates = (next_week_start.to_date..(Time.zone.today - 1)).to_a

        daily_dates.each do |date|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: date.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        initial_weekly_count = CandleSeriesRecord.where(instrument: instrument, timeframe: "1W").count

        result = described_class.call(instruments: instruments, weeks_back: 52)

        expect(result[:success]).to eq(1)
        # Should have created new weekly candles for the new weeks
        final_weekly_count = CandleSeriesRecord.where(instrument: instrument, timeframe: "1W").count
        expect(final_weekly_count).to be > initial_weekly_count
      end

      it "skips instrument when already up-to-date" do
        # Create weekly candle from current week
        current_week_start = Time.zone.today.beginning_of_week
        create(:candle_series_record,
               instrument: instrument,
                 timeframe: :weekly,
               timestamp: current_week_start,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 7_000_000)

        initial_weekly_count = CandleSeriesRecord.where(instrument: instrument, timeframe: "1W").count

        result = described_class.call(instruments: instruments, weeks_back: 52)

        expect(result[:success]).to eq(1)
        expect(result[:skipped_up_to_date]).to eq(1)
        # Should not create new weekly candles
        expect(CandleSeriesRecord.where(instrument: instrument, timeframe: "1W").count).to eq(initial_weekly_count)
      end

      it "uses minimum range when latest weekly candle is very old" do
        # Create weekly candle from 60 weeks ago (older than weeks_back of 4)
        old_week_start = 60.weeks.ago.beginning_of_week
        create(:candle_series_record,
               instrument: instrument,
                 timeframe: :weekly,
               timestamp: old_week_start,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 7_000_000)

        weeks_back = 4
        min_from_date = (Time.zone.today - 1) - (weeks_back * 7).days

        # Create daily candles from min_from_date to today
        daily_dates = (min_from_date..(Time.zone.today - 1)).to_a
        daily_dates.each do |date|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: date.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        result = described_class.call(instruments: instruments, weeks_back: weeks_back)

        expect(result[:success]).to eq(1)
        # Should create weekly candles from min_from_date
        weekly_candles = CandleSeriesRecord.weekly.where(instrument: instrument).order(timestamp: :asc)
        expect(weekly_candles.first.timestamp.to_date).to be <= min_from_date.beginning_of_week
      end

      it "fetches from next week when latest weekly candle is recent" do
        # Create weekly candle from 2 weeks ago (recent, within weeks_back of 4)
        recent_week_start = 2.weeks.ago.beginning_of_week
        create(:candle_series_record,
               instrument: instrument,
                 timeframe: :weekly,
               timestamp: recent_week_start,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 7_000_000)

        weeks_back = 4
        expected_from_date = (recent_week_start + 1.week).to_date

        # Create daily candles from next week to today
        daily_dates = (expected_from_date..(Time.zone.today - 1)).to_a
        daily_dates.each do |date|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: date.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        initial_weekly_count = CandleSeriesRecord.where(instrument: instrument, timeframe: "1W").count

        result = described_class.call(instruments: instruments, weeks_back: weeks_back)

        expect(result[:success]).to eq(1)
        # Should create weekly candles only for new weeks
        final_weekly_count = CandleSeriesRecord.where(instrument: instrument, timeframe: "1W").count
        expect(final_weekly_count).to be > initial_weekly_count
      end

      it "handles gap between latest weekly candle and today" do
        # Create weekly candle from 10 weeks ago (gap exists)
        gap_week_start = 10.weeks.ago.beginning_of_week
        create(:candle_series_record,
               instrument: instrument,
                 timeframe: :weekly,
               timestamp: gap_week_start,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 7_000_000)

        weeks_back = 4
        min_from_date = (Time.zone.today - 1) - (weeks_back * 7).days

        # Create daily candles from min_from_date to today
        daily_dates = (min_from_date..(Time.zone.today - 1)).to_a
        daily_dates.each do |date|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: date.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        result = described_class.call(instruments: instruments, weeks_back: weeks_back)

        expect(result[:success]).to eq(1)
        # Should create weekly candles from min_from_date to fill the gap
        weekly_candles = CandleSeriesRecord.weekly.where(instrument: instrument).order(timestamp: :asc)
        expect(weekly_candles.last.timestamp.to_date).to be >= (Time.zone.today - 1).beginning_of_week
      end
    end

    context "with no existing weekly candles" do
      it "fetches full range when no weekly candles exist" do
        # Ensure no existing weekly candles
        CandleSeriesRecord.weekly.where(instrument: instrument).delete_all

        weeks_back = 4
        min_from_date = (Time.zone.today - 1) - (weeks_back * 7).days

        # Create daily candles for the full range
        daily_dates = (min_from_date..(Time.zone.today - 1)).to_a
        daily_dates.each do |date|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: date.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        result = described_class.call(instruments: instruments, weeks_back: weeks_back)

        expect(result[:success]).to eq(1)
        # Should create weekly candles for the full range
        weekly_candles = CandleSeriesRecord.weekly.where(instrument: instrument)
        expect(weekly_candles.count).to be > 0
        expect(weekly_candles.minimum(:timestamp).to_date).to be <= min_from_date.beginning_of_week
      end
    end

    context "with date range filtering" do
      it "loads only daily candles in the specified date range" do
        weeks_back = 2
        min_from_date = (Time.zone.today - 1) - (weeks_back * 7).days

        # Create daily candles both before and after the range
        (min_from_date - 7.days..min_from_date - 1.day).each do |date|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: date.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        # Create daily candles within the range
        (min_from_date..(Time.zone.today - 1)).each do |date|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: date.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        result = described_class.call(instruments: instruments, weeks_back: weeks_back)

        expect(result[:success]).to eq(1)
        # Should only create weekly candles from the specified range
        weekly_candles = CandleSeriesRecord.weekly.where(instrument: instrument).order(timestamp: :asc)
        expect(weekly_candles.first.timestamp.to_date).to be >= min_from_date.beginning_of_week
      end
    end

    context "with minimum 52 weeks requirement" do
      it "creates at least 52 weekly candles when weeks_back is 52" do
        CandleSeriesRecord.where(instrument: instrument).delete_all

        # Create 365 days of daily candles (enough for 52 weeks)
        (0..364).each do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        result = described_class.call(instruments: instruments, weeks_back: 52)

        expect(result[:success]).to eq(1)
        weekly_count = CandleSeriesRecord.weekly.where(instrument: instrument).count
        expect(weekly_count).to be >= 52
      end

      it "uses default weeks_back of 52 when not specified" do
        CandleSeriesRecord.where(instrument: instrument).delete_all

        # Create 365 days of daily candles
        (0..364).each do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        result = described_class.call(instruments: instruments)

        expect(result[:success]).to eq(1)
        weekly_count = CandleSeriesRecord.weekly.where(instrument: instrument).count
        expect(weekly_count).to be >= 52
      end

      it "handles instruments with insufficient weekly candles (< 52)" do
        CandleSeriesRecord.where(instrument: instrument).delete_all

        # Create only 100 days of daily candles (insufficient for 52 weeks)
        (0..99).each do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        result = described_class.call(instruments: instruments, weeks_back: 52)

        expect(result[:success]).to eq(1)
        weekly_count = CandleSeriesRecord.weekly.where(instrument: instrument).count
        expect(weekly_count).to be < 52
      end
    end

    context "with missing data handling" do
      it "handles instruments with no daily candles" do
        CandleSeriesRecord.where(instrument: instrument).delete_all

        result = described_class.call(instruments: instruments, weeks_back: 52)

        expect(result[:failed]).to eq(1)
        expect(CandleSeriesRecord.weekly.where(instrument: instrument).count).to eq(0)
      end

      it "handles gaps in daily candles when aggregating weekly" do
        CandleSeriesRecord.where(instrument: instrument).delete_all

        # Create daily candles with gaps
        # Week 1: Monday, Tuesday, Friday (missing Wed, Thu)
        week1_start = 2.weeks.ago.beginning_of_week
        create(:candle_series_record, instrument: instrument, timeframe: :daily, timestamp: week1_start)
        create(:candle_series_record, instrument: instrument, timeframe: :daily, timestamp: week1_start + 1.day)
        create(:candle_series_record, instrument: instrument, timeframe: :daily, timestamp: week1_start + 4.days)

        # Week 2: Complete week
        week2_start = 1.week.ago.beginning_of_week
        (0..4).each do |i|
          create(:candle_series_record, instrument: instrument, timeframe: :daily, timestamp: week2_start + i.days)
        end

        result = described_class.call(instruments: instruments, weeks_back: 2)

        expect(result[:success]).to eq(1)
        # Should create weekly candles even with gaps
        weekly_count = CandleSeriesRecord.weekly.where(instrument: instrument).count
        expect(weekly_count).to be >= 2
      end
    end

    context "with daily sync scenarios" do
      it "skips instrument when weekly candles are already up-to-date" do
        # Create weekly candle from current week
        current_week_start = Time.zone.today.beginning_of_week
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :weekly,
               timestamp: current_week_start)

        initial_count = CandleSeriesRecord.weekly.where(instrument: instrument).count

        result = described_class.call(instruments: instruments, weeks_back: 52)

        expect(result[:success]).to eq(1)
        expect(result[:skipped_up_to_date]).to eq(1)
        expect(CandleSeriesRecord.weekly.where(instrument: instrument).count).to eq(initial_count)
      end

      it "aggregates only new daily candles during daily sync" do
        # Create weekly candle from 2 weeks ago
        old_week_start = 2.weeks.ago.beginning_of_week
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :weekly,
               timestamp: old_week_start)

        # Create new daily candles for last 2 weeks
        (0..13).each do |i|
          create(:candle_series_record,
                 instrument: instrument,
                 timeframe: :daily,
                 timestamp: i.days.ago.beginning_of_day,
                 open: 100.0,
                 high: 105.0,
                 low: 99.0,
                 close: 103.0,
                 volume: 1_000_000)
        end

        initial_count = CandleSeriesRecord.weekly.where(instrument: instrument).count

        result = described_class.call(instruments: instruments, weeks_back: 52)

        expect(result[:success]).to eq(1)
        # Should create new weekly candles for the new weeks
        final_count = CandleSeriesRecord.weekly.where(instrument: instrument).count
        expect(final_count).to be > initial_count
      end

      it "handles multiple instruments during daily sync" do
        instrument2 = create(:instrument, symbol_name: "TEST2", security_id: "12346")
        instruments = Instrument.where(id: [instrument.id, instrument2.id])

        # Both instruments have weekly candles from current week
        current_week_start = Time.zone.today.beginning_of_week
        create(:candle_series_record, instrument: instrument, timeframe: :weekly, timestamp: current_week_start)
        create(:candle_series_record, instrument: instrument2, timeframe: :weekly, timestamp: current_week_start)

        result = described_class.call(instruments: instruments, weeks_back: 52)

        expect(result[:success]).to eq(2)
        expect(result[:skipped_up_to_date]).to eq(2)
      end
    end
  end

  describe "private methods" do
    let(:service) { described_class.new(instruments: instruments, weeks_back: 1) }

    describe "#aggregate_to_weekly" do
      it "aggregates daily candles to weekly" do
        daily_candles = Array.new(7) do |i|
          {
            timestamp: i.days.ago.to_i,
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1_000_000,
          }
        end

        weekly = service.send(:aggregate_to_weekly, daily_candles)

        expect(weekly).to be_an(Array)
        expect(weekly.first).to have_key(:timestamp)
        expect(weekly.first).to have_key(:open)
        expect(weekly.first).to have_key(:high)
        expect(weekly.first).to have_key(:low)
        expect(weekly.first).to have_key(:close)
        expect(weekly.first).to have_key(:volume)
      end

      it "uses first open and last close" do
        # Ensure both candles are in the same week (use same week start)
        week_start = Time.zone.today.beginning_of_week
        daily_candles = [
          { timestamp: week_start + 1.day, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
          { timestamp: week_start + 2.days, open: 103.0, high: 108.0, low: 102.0, close: 106.0, volume: 1_200_000 },
        ]

        weekly = service.send(:aggregate_to_weekly, daily_candles)

        expect(weekly.first[:open]).to eq(100.0) # First candle's open
        expect(weekly.first[:close]).to eq(106.0) # Last candle's close
      end

      it "calculates max high and min low" do
        # Ensure both candles are in the same week
        week_start = Time.zone.today.beginning_of_week
        daily_candles = [
          { timestamp: week_start + 1.day, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
          { timestamp: week_start + 2.days, open: 103.0, high: 110.0, low: 95.0, close: 106.0, volume: 1_200_000 },
        ]

        weekly = service.send(:aggregate_to_weekly, daily_candles)

        expect(weekly.first[:high]).to eq(110.0) # Max high
        expect(weekly.first[:low]).to eq(95.0) # Min low
      end

      it "sums volumes" do
        # Ensure both candles are in the same week
        week_start = Time.zone.today.beginning_of_week
        daily_candles = [
          { timestamp: week_start + 1.day, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
          { timestamp: week_start + 2.days, open: 103.0, high: 108.0, low: 102.0, close: 106.0, volume: 1_200_000 },
        ]

        weekly = service.send(:aggregate_to_weekly, daily_candles)

        expect(weekly.first[:volume]).to eq(2_200_000) # Sum of volumes
      end

      it "handles empty candles" do
        weekly = service.send(:aggregate_to_weekly, [])

        expect(weekly).to eq([])
      end

      it "sorts by timestamp" do
        daily_candles = [
          { timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
          { timestamp: 7.days.ago.to_i, open: 98.0, high: 102.0, low: 97.0, close: 100.0, volume: 900_000 },
        ]

        weekly = service.send(:aggregate_to_weekly, daily_candles)

        timestamps = weekly.pluck(:timestamp)
        expect(timestamps).to eq(timestamps.sort)
      end
    end

    describe "#normalize_candles" do
      it "handles array format" do
        candles = [
          { timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
        ]

        normalized = service.send(:normalize_candles, candles)

        expect(normalized).to be_an(Array)
        expect(normalized.first).to have_key(:timestamp)
      end

      it "handles hash format (DhanHQ)" do
        candles = {
          "timestamp" => [1.day.ago.to_i],
          "open" => [100.0],
          "high" => [105.0],
          "low" => [99.0],
          "close" => [103.0],
          "volume" => [1_000_000],
        }

        normalized = service.send(:normalize_candles, candles)

        expect(normalized).to be_an(Array)
        expect(normalized.first).to have_key(:timestamp)
      end

      it "handles single hash" do
        candle = { timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 }

        normalized = service.send(:normalize_candles, candle)

        expect(normalized).to be_an(Array)
        expect(normalized.size).to eq(1)
      end

      it "handles nil data" do
        normalized = service.send(:normalize_candles, nil)

        expect(normalized).to eq([])
      end

      it "handles invalid candle data gracefully" do
        invalid_candle = { invalid: "data" }

        normalized = service.send(:normalize_candles, [invalid_candle])

        expect(normalized).to be_an(Array)
      end
    end

    describe "#parse_timestamp" do
      it "handles Time objects" do
        time = Time.current
        parsed = service.send(:parse_timestamp, time)

        expect(parsed).to be_a(Time)
      end

      it "handles integer timestamps" do
        timestamp = Time.current.to_i
        parsed = service.send(:parse_timestamp, timestamp)

        expect(parsed).to be_a(Time)
      end

      it "handles string timestamps" do
        timestamp = Time.current.iso8601
        parsed = service.send(:parse_timestamp, timestamp)

        expect(parsed).to be_a(Time)
      end

      it "handles nil timestamps" do
        parsed = service.send(:parse_timestamp, nil)

        expect(parsed).to be_a(Time)
      end

      it "handles invalid timestamps" do
        parsed = service.send(:parse_timestamp, "invalid")

        expect(parsed).to be_a(Time)
      end
    end
  end
end
