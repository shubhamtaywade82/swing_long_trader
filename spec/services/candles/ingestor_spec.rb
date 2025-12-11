# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::Ingestor, type: :service do
  let(:instrument) { create(:instrument) }

  describe '.upsert_candles' do
    it 'upserts candles successfully' do
      candles_data = [
        {
          timestamp: 1.day.ago,
          open: 100.0,
          high: 105.0,
          low: 99.0,
          close: 103.0,
          volume: 1_000_000
        },
        {
          timestamp: 2.days.ago,
          open: 98.0,
          high: 102.0,
          low: 97.0,
          close: 100.0,
          volume: 900_000
        }
      ]

      result = described_class.upsert_candles(
        instrument: instrument,
        timeframe: '1D',
        candles_data: candles_data
      )

      expect(result[:success]).to be true
      expect(result[:upserted]).to eq(2)
      expect(CandleSeriesRecord.count).to eq(2)
    end

    it 'skips duplicate candles' do
      # Create existing candle with normalized timestamp (beginning of day)
      # Use a fixed time to avoid timezone issues
      base_time = Time.zone.parse('2024-12-10 14:30:00')
      normalized_timestamp = base_time.beginning_of_day

      # Create the existing candle with exact values
      existing_candle = create(:daily_candle,
        instrument: instrument,
        timestamp: normalized_timestamp,
        close: 100.0,
        open: 100.0,
        high: 105.0,
        low: 99.0,
        volume: 1_000_000
      )

      # Reload to ensure we have the exact database values
      existing_candle.reload

      candles_data = [
        {
          timestamp: base_time.to_i, # Pass as integer timestamp, will be normalized to beginning_of_day
          open: existing_candle.open, # Use exact same values from database
          high: existing_candle.high,
          low: existing_candle.low,
          close: existing_candle.close,
          volume: existing_candle.volume
        }
      ]

      result = described_class.upsert_candles(
        instrument: instrument,
        timeframe: '1D',
        candles_data: candles_data
      )

      expect(result[:success]).to be true
      expect(result[:skipped]).to eq(1), "Expected 1 skipped, got #{result.inspect}. Existing candle: #{existing_candle.inspect}"
      expect(CandleSeriesRecord.count).to eq(1) # Still only 1
    end

    it 'updates candle if data changed' do
      # Create existing candle
      create(:daily_candle, instrument: instrument, timestamp: 1.day.ago, close: 100.0)

      candles_data = [
        {
          timestamp: 1.day.ago,
          open: 100.0,
          high: 105.0,
          low: 99.0,
          close: 105.0, # Changed
          volume: 1_000_000
        }
      ]

      result = described_class.upsert_candles(
        instrument: instrument,
        timeframe: '1D',
        candles_data: candles_data
      )

      expect(result[:success]).to be true
      expect(result[:upserted]).to eq(1)
      expect(CandleSeriesRecord.first.close.to_f).to eq(105.0)
    end
  end
end

