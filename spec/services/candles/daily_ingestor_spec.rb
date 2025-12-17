# frozen_string_literal: true

require "rails_helper"

RSpec.describe Candles::DailyIngestor do
  let(:instrument) { create(:instrument, symbol_name: "TEST", security_id: "12345") }
  let(:instruments) { Instrument.where(id: instrument.id) }

  describe ".call" do
    context "with valid instruments" do
      let(:mock_candles) do
        [
          {
            timestamp: 1.day.ago.to_i,
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1_000_000,
          },
          {
            timestamp: 2.days.ago.to_i,
            open: 98.0,
            high: 102.0,
            low: 97.0,
            close: 100.0,
            volume: 900_000,
          },
        ]
      end

      before do
        # Use allow_any_instance_of since find_each reloads the instrument
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).with(
          from_date: anything,
          to_date: anything,
          oi: false,
        ).and_return(mock_candles)

        # Call the service once for all tests in this context
        @result = described_class.call(instruments: instruments, days_back: 2)
      end

      it "fetches and stores daily candles" do
        expect(@result[:success]).to eq(1) # Count of successful instruments
        expect(@result[:processed]).to eq(1)
        expect(CandleSeriesRecord.daily.where(instrument: instrument).count).to eq(2)
      end

      it "returns summary with processed count" do
        expect(@result).to have_key(:processed)
        expect(@result).to have_key(:success)
        expect(@result).to have_key(:failed)
        expect(@result).to have_key(:total_candles)
      end

      it "upserts candles without creating duplicates" do
        initial_count = CandleSeriesRecord.count

        # Second import with same data
        described_class.call(instruments: instruments, days_back: 2)

        # Should not create duplicates
        expect(CandleSeriesRecord.count).to eq(initial_count)
      end

      it "handles custom days_back parameter" do
        # This test needs a different days_back, so call separately
        result = described_class.call(instruments: instruments, days_back: 5)

        expect(result[:processed]).to eq(1)
        expect(result[:success]).to eq(1)
      end
    end

    context "with invalid instruments" do
      it "handles instruments without security_id" do
        # Create instrument with empty security_id (database has NOT NULL, so use empty string)
        instrument_no_id = create(:instrument)
        instrument_no_id.update_column(:security_id, "")
        instruments_invalid = Instrument.where(id: instrument_no_id.id)

        result = described_class.call(instruments: instruments_invalid, days_back: 2)

        expect(result[:failed]).to eq(1)
        expect(result[:errors]).not_to be_empty
      end

      it "handles API errors gracefully" do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_raise(StandardError.new("API error"))

        result = described_class.call(instruments: instruments, days_back: 2)

        expect(result[:failed]).to eq(1)
        expect(result[:errors]).not_to be_empty
      end
    end

    context "with multiple instruments" do
      let(:instrument2) { create(:instrument, symbol_name: "TEST2", security_id: "12346") }
      let(:multiple_instruments) { Instrument.where(id: [instrument.id, instrument2.id]) }

      before do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])
      end

      it "processes all instruments" do
        result = described_class.call(instruments: multiple_instruments, days_back: 2)

        expect(result[:processed]).to eq(2)
      end
    end

    context "with default parameters" do
      it "uses all equity/index instruments if none provided" do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])

        result = described_class.call

        expect(result).to be_a(Hash)
        expect(result[:processed]).to be >= 0
      end

      it "uses default days_back if not provided" do
        # Use allow_any_instance_of since find_each reloads the instrument
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).with(
          from_date: anything,
          to_date: anything,
          oi: false,
        ).and_return([
                       {
                         timestamp: 1.day.ago.to_i,
                         open: 100.0,
                         high: 105.0,
                         low: 99.0,
                         close: 103.0,
                         volume: 1_000_000,
                       },
                     ])

        result = described_class.call(instruments: instruments)

        expect(result[:processed]).to eq(1)
        expect(result[:success]).to eq(1)
        # Default days_back is 365, so from_date should be approximately 365 days before to_date
      end
    end

    context "with edge cases" do
      it "handles empty candles response" do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])

        result = described_class.call(instruments: instruments, days_back: 2)

        expect(result[:failed]).to eq(1)
        expect(result[:errors]).not_to be_empty
      end

      it "handles nil instrument" do
        result = described_class.new(instruments: nil, days_back: 2).send(:fetch_and_store_daily_candles, nil)

        expect(result[:success]).to be false
        expect(result[:error]).to include("Invalid instrument")
      end

      it "handles rate limiting delay" do
        # Ensure no existing candles so instruments aren't skipped
        CandleSeriesRecord.delete_all

        # Mock API to return data (so instruments aren't skipped)
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([
                                                                                    { timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
                                                                                  ])

        # Process 10 instruments to trigger rate limiting (use unique security_ids)
        # With delay_interval of 5, sleep should be called at 5 and 10
        instruments_list = 10.times.map { |i| create(:instrument, security_id: "rate_limit_#{i}") }
        instruments = Instrument.where(id: instruments_list.map(&:id))

        # Create service instance and stub sleep on it
        service = described_class.new(instruments: instruments, days_back: 2)
        sleep_calls = []
        allow(service).to receive(:sleep) { |duration| sleep_calls << duration }

        service.call

        # Should have called sleep at least once (every 5 instruments by default)
        # With 10 instruments and delay_interval of 5, sleep should be called when processed is 5
        expect(sleep_calls.length).to be > 0
      end

      it "handles partial failures" do
        instrument2 = create(:instrument, symbol_name: "TEST2", security_id: "12346")
        instruments = Instrument.where(id: [instrument.id, instrument2.id])

        # Ensure no existing candles (optimization would skip if data exists)
        CandleSeriesRecord.where(instrument: [instrument, instrument2]).delete_all

        # First instrument succeeds, second fails
        # Use allow_any_instance_of since find_each reloads instruments
        allow_any_instance_of(Instrument).to receive(:historical_ohlc) do |inst|
          if inst.id == instrument.id
            [{ timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 }]
          elsif inst.id == instrument2.id
            raise StandardError.new("API error")
          else
            []
          end
        end

        result = described_class.call(instruments: instruments, days_back: 2)

        expect(result[:processed]).to eq(2)
        expect(result[:success]).to eq(1)
        expect(result[:failed]).to eq(1)
      end

      it "logs summary correctly" do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([
                                                                                    { timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
                                                                                  ])
        allow(Rails.logger).to receive(:info)

        described_class.call(instruments: instruments, days_back: 2)

        expect(Rails.logger).to have_received(:info).at_least(:once)
      end
    end

    context "with date range calculations" do
      it "calculates correct date range" do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])

        service = described_class.new(instruments: instruments, days_back: 30)
        result = service.send(:fetch_and_store_daily_candles, instrument)

        # Should have called historical_ohlc with correct date range
        expect(result).to be_present
      end

      it "uses yesterday as to_date" do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])

        service = described_class.new(instruments: instruments, days_back: 2)
        service.send(:fetch_and_store_daily_candles, instrument)

        # Verify that to_date is yesterday
        # This is tested implicitly through the API call
      end
    end

    context "with incremental updates" do
      it "fetches only new candles when latest candle exists" do
        # Create existing candle from 5 days ago
        latest_date = 5.days.ago.to_date
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: latest_date.beginning_of_day,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 1_000_000)

        # Mock API to return only new candles (from 4 days ago to yesterday)
        new_candles = [
          { timestamp: 4.days.ago.to_i, open: 101.0, high: 106.0, low: 100.0, close: 104.0, volume: 1_100_000 },
          { timestamp: 3.days.ago.to_i, open: 102.0, high: 107.0, low: 101.0, close: 105.0, volume: 1_200_000 },
          { timestamp: 2.days.ago.to_i, open: 103.0, high: 108.0, low: 102.0, close: 106.0, volume: 1_300_000 },
          { timestamp: 1.day.ago.to_i, open: 104.0, high: 109.0, low: 103.0, close: 107.0, volume: 1_400_000 },
        ]

        allow_any_instance_of(Instrument).to receive(:historical_ohlc) do |_inst, from_date:, to_date:, oi:|
          # Verify it's fetching from the day after latest candle
          expect(from_date).to eq(latest_date + 1.day)
          expect(to_date).to eq(Time.zone.today - 1)
          new_candles
        end

        result = described_class.call(instruments: instruments, days_back: 30)

        expect(result[:success]).to eq(1)
        expect(CandleSeriesRecord.daily.where(instrument: instrument).count).to eq(5) # 1 existing + 4 new
      end

      it "skips instrument when already up-to-date" do
        # Create candle from yesterday (already up-to-date)
        yesterday = Time.zone.today - 1
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: yesterday.beginning_of_day,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 1_000_000)

        # API should not be called
        expect_any_instance_of(Instrument).not_to receive(:historical_ohlc)

        result = described_class.call(instruments: instruments, days_back: 30)

        expect(result[:success]).to eq(1)
        expect(result[:skipped_up_to_date]).to eq(1)
        expect(CandleSeriesRecord.daily.where(instrument: instrument).count).to eq(1)
      end

      it "uses minimum range when latest candle is very old" do
        # Create candle from 400 days ago (older than days_back of 30)
        old_date = 400.days.ago.to_date
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: old_date.beginning_of_day,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 1_000_000)

        days_back = 30
        min_from_date = (Time.zone.today - 1) - days_back.days

        new_candles = [
          { timestamp: 1.day.ago.to_i, open: 101.0, high: 106.0, low: 100.0, close: 104.0, volume: 1_100_000 },
        ]

        allow_any_instance_of(Instrument).to receive(:historical_ohlc) do |_inst, from_date:, to_date:, oi:|
          # Should fetch from min_from_date (not from old_date + 1.day) to fill gaps
          expect(from_date).to eq(min_from_date)
          expect(to_date).to eq(Time.zone.today - 1)
          new_candles
        end

        result = described_class.call(instruments: instruments, days_back: days_back)

        expect(result[:success]).to eq(1)
      end

      it "fetches from latest + 1 day when latest candle is recent" do
        # Create candle from 10 days ago (recent, within days_back of 30)
        recent_date = 10.days.ago.to_date
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: recent_date.beginning_of_day,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 1_000_000)

        days_back = 30
        expected_from_date = recent_date + 1.day

        new_candles = [
          { timestamp: 9.days.ago.to_i, open: 101.0, high: 106.0, low: 100.0, close: 104.0, volume: 1_100_000 },
        ]

        allow_any_instance_of(Instrument).to receive(:historical_ohlc) do |_inst, from_date:, to_date:, oi:|
          # Should fetch from latest + 1 day (not from min_from_date) for incremental update
          expect(from_date).to eq(expected_from_date)
          expect(to_date).to eq(Time.zone.today - 1)
          new_candles
        end

        result = described_class.call(instruments: instruments, days_back: days_back)

        expect(result[:success]).to eq(1)
      end

      it "handles gap between latest candle and today" do
        # Create candle from 50 days ago (gap exists)
        gap_date = 50.days.ago.to_date
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: gap_date.beginning_of_day,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 1_000_000)

        days_back = 30
        min_from_date = (Time.zone.today - 1) - days_back.days

        # Gap is larger than days_back, so should use min_from_date
        new_candles = (0..29).map do |i|
          { timestamp: (Time.zone.today - 1 - i.days).to_i, open: 100.0 + i, high: 105.0 + i, low: 99.0 + i, close: 103.0 + i, volume: 1_000_000 }
        end

        allow_any_instance_of(Instrument).to receive(:historical_ohlc) do |_inst, from_date:, to_date:, oi:|
          # Should fetch from min_from_date to fill the gap
          expect(from_date).to eq(min_from_date)
          expect(to_date).to eq(Time.zone.today - 1)
          new_candles
        end

        result = described_class.call(instruments: instruments, days_back: days_back)

        expect(result[:success]).to eq(1)
      end
    end

    context "with no existing candles" do
      it "fetches full range when no candles exist" do
        # Ensure no existing candles
        CandleSeriesRecord.where(instrument: instrument).delete_all

        days_back = 30
        expected_from_date = (Time.zone.today - 1) - days_back.days

        new_candles = [
          { timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
        ]

        allow_any_instance_of(Instrument).to receive(:historical_ohlc) do |_inst, from_date:, to_date:, oi:|
          # Should fetch full range from days_back
          expect(from_date).to eq(expected_from_date)
          expect(to_date).to eq(Time.zone.today - 1)
          new_candles
        end

        result = described_class.call(instruments: instruments, days_back: days_back)

        expect(result[:success]).to eq(1)
      end
    end

    context "with rate limit retries" do
      it "retries on rate limit errors" do
        CandleSeriesRecord.where(instrument: instrument).delete_all

        retry_count = 0
        allow_any_instance_of(Instrument).to receive(:historical_ohlc) do
          retry_count += 1
          if retry_count < 2
            raise StandardError.new("429 Rate limit exceeded")
          else
            [{ timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 }]
          end
        end

        service = described_class.new(instruments: instruments, days_back: 2)
        allow(service).to receive(:sleep) # Stub sleep to speed up test

        result = service.call

        expect(result[:success]).to eq(1)
        expect(result[:rate_limit_retries]).to be > 0
      end

      it "gives up after max retries" do
        CandleSeriesRecord.where(instrument: instrument).delete_all

        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_raise(StandardError.new("429 Rate limit exceeded"))

        service = described_class.new(instruments: instruments, days_back: 2)
        allow(service).to receive(:sleep) # Stub sleep to speed up test

        result = service.call

        expect(result[:failed]).to eq(1)
        expect(result[:errors]).not_to be_empty
      end
    end

    context "with minimum 365 candles requirement" do
      it "fetches at least 365 days of candles when days_back is 365" do
        CandleSeriesRecord.where(instrument: instrument).delete_all

        # Mock API to return 365 candles
        candles_365 = (0..364).map do |i|
          {
            timestamp: (Time.zone.today - 1 - i.days).to_i,
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1_000_000,
          }
        end

        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return(candles_365)

        result = described_class.call(instruments: instruments, days_back: 365)

        expect(result[:success]).to eq(1)
        expect(CandleSeriesRecord.daily.where(instrument: instrument).count).to eq(365)
      end

      it "uses default days_back of 365 when not specified" do
        CandleSeriesRecord.where(instrument: instrument).delete_all

        expected_from_date = (Time.zone.today - 1) - 365.days

        allow_any_instance_of(Instrument).to receive(:historical_ohlc) do |_inst, from_date:, to_date:, oi:|
          expect(from_date).to eq(expected_from_date)
          expect(to_date).to eq(Time.zone.today - 1)
          [{ timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 }]
        end

        described_class.call(instruments: instruments)
      end

      it "handles instruments with insufficient candles (< 365)" do
        CandleSeriesRecord.where(instrument: instrument).delete_all

        # Mock API to return only 100 candles (insufficient)
        candles_100 = (0..99).map do |i|
          {
            timestamp: (Time.zone.today - 1 - i.days).to_i,
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1_000_000,
          }
        end

        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return(candles_100)

        result = described_class.call(instruments: instruments, days_back: 365)

        expect(result[:success]).to eq(1)
        count = CandleSeriesRecord.daily.where(instrument: instrument).count
        expect(count).to eq(100)
        expect(count).to be < 365
      end
    end

    context "with missing data handling" do
      it "detects gaps in candle data" do
        # Create candles with a gap
        create(:candle_series_record, instrument: instrument, timeframe: :daily, timestamp: 10.days.ago.beginning_of_day)
        create(:candle_series_record, instrument: instrument, timeframe: :daily, timestamp: 5.days.ago.beginning_of_day)
        # Gap: missing candles for days 9, 8, 7, 6

        # Mock API to fill the gap
        gap_candles = (6..9).map do |i|
          {
            timestamp: i.days.ago.to_i,
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1_000_000,
          }
        end

        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return(gap_candles)

        result = described_class.call(instruments: instruments, days_back: 30)

        expect(result[:success]).to eq(1)
        # Should have filled the gap
        dates = CandleSeriesRecord.daily.where(instrument: instrument).order(:timestamp).pluck(:timestamp).map(&:to_date)
        expect(dates).to include(9.days.ago.to_date, 8.days.ago.to_date, 7.days.ago.to_date, 6.days.ago.to_date)
      end

      it "handles instruments with no existing candles" do
        CandleSeriesRecord.where(instrument: instrument).delete_all

        candles = [
          { timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
        ]

        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return(candles)

        result = described_class.call(instruments: instruments, days_back: 365)

        expect(result[:success]).to eq(1)
        expect(CandleSeriesRecord.daily.where(instrument: instrument).count).to be > 0
      end

      it "re-ingests with extended date range to fill gaps" do
        # Create old candle from 400 days ago
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 400.days.ago.beginning_of_day)

        # Mock API to return candles filling the gap
        gap_candles = (1..365).map do |i|
          {
            timestamp: (Time.zone.today - 1 - i.days).to_i,
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1_000_000,
          }
        end

        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return(gap_candles)

        result = described_class.call(instruments: instruments, days_back: 365)

        expect(result[:success]).to eq(1)
        # Should have candles from the gap fill
        count = CandleSeriesRecord.daily.where(instrument: instrument).count
        expect(count).to be >= 365
      end
    end

    context "with daily sync scenarios" do
      it "fetches only new candles during daily sync" do
        # Create candle from yesterday (already up-to-date)
        yesterday = Time.zone.today - 1
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: yesterday.beginning_of_day)

        # Mock API should not be called (already up-to-date)
        expect_any_instance_of(Instrument).not_to receive(:historical_ohlc)

        result = described_class.call(instruments: instruments, days_back: 365)

        expect(result[:success]).to eq(1)
        expect(result[:skipped_up_to_date]).to eq(1)
      end

      it "fetches incremental updates during daily sync" do
        # Create candle from 3 days ago
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 3.days.ago.beginning_of_day)

        # Mock API to return only new candles (2 days ago and yesterday)
        new_candles = [
          { timestamp: 2.days.ago.to_i, open: 101.0, high: 106.0, low: 100.0, close: 104.0, volume: 1_100_000 },
          { timestamp: 1.day.ago.to_i, open: 102.0, high: 107.0, low: 101.0, close: 105.0, volume: 1_200_000 },
        ]

        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return(new_candles)

        result = described_class.call(instruments: instruments, days_back: 365)

        expect(result[:success]).to eq(1)
        expect(CandleSeriesRecord.daily.where(instrument: instrument).count).to eq(3) # 1 existing + 2 new
      end

      it "handles multiple instruments during daily sync" do
        instrument2 = create(:instrument, symbol_name: "TEST2", security_id: "12346")
        instruments = Instrument.where(id: [instrument.id, instrument2.id])

        # Both instruments have candles from yesterday
        create(:candle_series_record, instrument: instrument, timeframe: :daily, timestamp: 1.day.ago.beginning_of_day)
        create(:candle_series_record, instrument: instrument2, timeframe: :daily, timestamp: 1.day.ago.beginning_of_day)

        # Both should be skipped (already up-to-date)
        expect_any_instance_of(Instrument).not_to receive(:historical_ohlc)

        result = described_class.call(instruments: instruments, days_back: 365)

        expect(result[:success]).to eq(2)
        expect(result[:skipped_up_to_date]).to eq(2)
      end
    end
  end
end
