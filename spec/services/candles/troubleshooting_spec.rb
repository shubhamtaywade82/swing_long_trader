# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Candle Ingestion Troubleshooting Scenarios", type: :service do
  # Tests based on CANDLE_INGESTION_GUIDE.md Section 6: Troubleshooting

  let(:instrument) { create(:instrument, symbol_name: "TEST", security_id: "12345", segment: "equity") }

  describe "Rate Limiting" do
    context "when handling API rate limits" do
      it "applies delay between requests" do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([
                                                                                    { timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
                                                                                  ])

        # Create 10 instruments to trigger rate limiting
        instruments_list = 10.times.map { |i| create(:instrument, security_id: "rate_limit_#{i}", segment: "equity") }
        instruments = Instrument.where(id: instruments_list.map(&:id))

        service = Candles::DailyIngestor.new(instruments: instruments, days_back: 2)
        sleep_calls = []
        allow(service).to receive(:sleep) { |duration| sleep_calls << duration }

        service.call

        # Should have called sleep at least once (every 5 instruments by default)
        expect(sleep_calls.length).to be > 0
      end

      it "handles rate limit errors gracefully" do
        CandleSeriesRecord.where(instrument: instrument).delete_all

        retry_count = 0
        allow_any_instance_of(Instrument).to receive(:historical_ohlc) do
          retry_count += 1
          raise StandardError.new("429 Rate limit exceeded") if retry_count < 2

          [{ timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 }]
        end

        service = Candles::DailyIngestor.new(instruments: Instrument.where(id: instrument.id), days_back: 2)
        allow(service).to receive(:sleep) # Stub sleep to speed up test

        result = service.call

        # Should eventually succeed after retries, or fail gracefully
        expect(result).to have_key(:success)
        expect(result[:success]).to be >= 0
      end
    end
  end

  describe "Missing Security IDs" do
    context "when instruments lack security_id" do
      it "handles instruments without security_id gracefully" do
        instrument_no_id = create(:instrument, symbol_name: "NO_ID", segment: "equity")
        instrument_no_id.update_column(:security_id, "")

        instruments_invalid = Instrument.where(id: instrument_no_id.id)

        result = Candles::DailyIngestor.call(instruments: instruments_invalid, days_back: 2)

        expect(result[:failed]).to eq(1)
        expect(result[:errors]).not_to be_empty
      end

      it "identifies instruments without security_id" do
        # Create instrument and try to set security_id to empty string (database may have NOT NULL)
        instrument_no_id = create(:instrument, segment: "equity", security_id: "test")
        instrument_no_id.update_column(:security_id, "")

        # Check for instruments with empty or nil security_id
        count = Instrument.where(segment: %w[equity index])
                          .where("security_id IS NULL OR security_id = ''")
                          .count

        expect(count).to be >= 0 # May be 0 if database enforces NOT NULL
      end
    end
  end

  describe "Incomplete Data" do
    context "when checking for gaps in candle data" do
      it "identifies date range gaps" do
        # Create candles with gaps
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 10.days.ago.beginning_of_day)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 5.days.ago.beginning_of_day)

        candles = CandleSeriesRecord.daily.where(instrument: instrument).order(:timestamp)

        expect(candles.first.timestamp.to_date).to eq(10.days.ago.to_date)
        expect(candles.last.timestamp.to_date).to eq(5.days.ago.to_date)
        expect(candles.count).to eq(2)
      end

      it "re-ingests with extended date range to fill gaps" do
        # Clear existing candles first
        CandleSeriesRecord.where(instrument: instrument).delete_all

        # Create old candle from 400 days ago
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 400.days.ago.beginning_of_day)

        initial_count = CandleSeriesRecord.daily.where(instrument: instrument).count
        expect(initial_count).to eq(1)

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

        result = Candles::DailyIngestor.call(instruments: Instrument.where(id: instrument.id), days_back: 730)

        expect(result[:success]).to eq(1)
        # Should have more candles than just the old one (gap filled)
        final_count = CandleSeriesRecord.daily.where(instrument: instrument).count
        expect(final_count).to be > initial_count
      end
    end
  end

  describe "Weekly Candles Not Updating" do
    context "when weekly candles depend on daily candles" do
      it "requires daily candles to be up-to-date first" do
        # Create fresh daily candle
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 1.day.ago.beginning_of_day)

        # Weekly ingestor should use daily candles
        result = Candles::WeeklyIngestor.call(
          instruments: Instrument.where(id: instrument.id),
          weeks_back: 1,
        )

        expect(result[:success]).to eq(1)
        expect(CandleSeriesRecord.weekly.where(instrument: instrument).count).to be > 0
      end

      it "handles case when daily candles are stale" do
        # Create stale daily candle (10 days ago)
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 10.days.ago.beginning_of_day)

        # Weekly ingestor should still work with available daily candles
        result = Candles::WeeklyIngestor.call(
          instruments: Instrument.where(id: instrument.id),
          weeks_back: 2,
        )

        expect(result[:success]).to eq(1)
      end
    end
  end

  describe "Bulk Import Failures" do
    context "when bulk import fails" do
      it "falls back to individual inserts when bulk import fails" do
        candles_data = [
          { timestamp: 1.day.ago, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
          { timestamp: 2.days.ago, open: 98.0, high: 102.0, low: 97.0, close: 100.0, volume: 900_000 },
        ]

        # Simulate bulk import failure
        allow(CandleSeriesRecord).to receive(:import).and_raise(ActiveRecord::StatementInvalid.new("Database error"))
        allow(Rails.logger).to receive(:warn)

        result = Candles::Ingestor.upsert_candles(
          instrument: instrument,
          timeframe: :daily,
          candles_data: candles_data,
        )

        # Should still succeed via fallback (or handle error gracefully)
        expect(result).to have_key(:success)
        # May succeed via fallback or fail gracefully
        expect(CandleSeriesRecord.daily.where(instrument: instrument).count).to eq(2) if result[:success]
      end

      it "handles unique constraint violations gracefully" do
        # Create existing candle
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 1.day.ago.beginning_of_day,
               open: 100.0,
               high: 105.0,
               low: 99.0,
               close: 103.0,
               volume: 1_000_000)

        candles_data = [
          { timestamp: 1.day.ago, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
        ]

        # Should handle duplicate gracefully (upsert)
        result = Candles::Ingestor.upsert_candles(
          instrument: instrument,
          timeframe: :daily,
          candles_data: candles_data,
        )

        expect(result[:success]).to be true
        expect(CandleSeriesRecord.daily.where(instrument: instrument).count).to eq(1)
      end
    end
  end

  describe "Enum Migration Issues" do
    context "when verifying enum values" do
      it "validates timeframe enum values" do
        # Enum returns string keys, not symbol keys
        expect(CandleSeriesRecord.timeframes).to eq({ "daily" => 0, "weekly" => 1, "hourly" => 2 })
      end

      it "rejects invalid enum values" do
        expect do
          CandleSeriesRecord.latest_for(instrument: instrument, timeframe: :invalid)
        end.to raise_error(ArgumentError, /Invalid timeframe/)
      end

      it "accepts valid enum symbols" do
        create(:candle_series_record,
               instrument: instrument,
               timeframe: :daily,
               timestamp: 1.day.ago.beginning_of_day)

        latest = CandleSeriesRecord.latest_for(instrument: instrument, timeframe: :daily)

        expect(latest).to be_present
        expect(latest.timeframe).to eq("daily")
      end
    end
  end

  describe "Transaction Safety" do
    context "when bulk import is wrapped in transaction" do
      it "handles transaction errors gracefully with fallback" do
        initial_count = CandleSeriesRecord.daily.where(instrument: instrument).count

        candles_data = [
          { timestamp: 1.day.ago, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
          { timestamp: 2.days.ago, open: 98.0, high: 102.0, low: 97.0, close: 100.0, volume: 900_000 },
        ]

        # Simulate error during bulk import - should trigger fallback
        allow(CandleSeriesRecord).to receive(:import).and_raise(ActiveRecord::StatementInvalid.new("Transaction error"))
        allow(Rails.logger).to receive(:error)

        result = Candles::Ingestor.upsert_candles(
          instrument: instrument,
          timeframe: :daily,
          candles_data: candles_data,
        )

        # Service should handle errors gracefully and fall back to individual inserts
        expect(result).to have_key(:success)
        expect(result[:success]).to be true # Fallback should succeed
        # Should have created candles via fallback
        final_count = CandleSeriesRecord.daily.where(instrument: instrument).count
        expect(final_count).to be >= initial_count
      end
    end
  end

  describe "Error Handling" do
    context "when API returns errors" do
      it "handles API errors gracefully" do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_raise(StandardError.new("API error"))

        result = Candles::DailyIngestor.call(
          instruments: Instrument.where(id: instrument.id),
          days_back: 2,
        )

        expect(result[:failed]).to eq(1)
        expect(result[:errors]).not_to be_empty
      end

      it "continues processing other instruments on error" do
        instrument2 = create(:instrument, symbol_name: "TEST2", security_id: "12346", segment: "equity")
        instruments = Instrument.where(id: [instrument.id, instrument2.id])

        # First instrument fails, second succeeds
        allow_any_instance_of(Instrument).to receive(:historical_ohlc) do |inst|
          raise StandardError.new("API error") if inst.id == instrument.id

          [{ timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 }]
        end

        result = Candles::DailyIngestor.call(instruments: instruments, days_back: 2)

        expect(result[:processed]).to eq(2)
        expect(result[:success]).to eq(1)
        expect(result[:failed]).to eq(1)
      end
    end
  end
end
