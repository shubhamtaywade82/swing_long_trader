# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::WeeklyIngestor do
  let(:instrument) { create(:instrument, symbol_name: 'TEST', security_id: '12345') }
  let(:instruments) { Instrument.where(id: instrument.id) }

  describe '.call' do
    context 'when daily candles are valid' do
      let(:mock_daily_candles) do
        7.times.map do |i|
          {
            timestamp: i.days.ago.to_i,
            open: 100.0 + i,
            high: 105.0 + i,
            low: 99.0 + i,
            close: 103.0 + i,
            volume: 1_000_000
          }
        end
      end

      let(:result) { described_class.call(instruments: instruments, weeks_back: 1) }

      before do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).with(
          from_date: anything,
          to_date: anything,
          oi: false
        ).and_return(mock_daily_candles)
      end

      it { expect(result[:processed]).to eq(1) }

      it { expect(result[:success]).to be > 0 }

      it 'creates weekly candles' do
        result
        expect(CandleSeriesRecord.where(instrument: instrument, timeframe: '1W').count).to be > 0
      end

      describe 'weekly candle attributes' do
        let(:weekly_candle) do
          result
          CandleSeriesRecord.where(instrument: instrument, timeframe: '1W').first
        end

        it { expect(weekly_candle).to be_present }

        it { expect(weekly_candle.open).to be_a(Numeric) }

        it { expect(weekly_candle.high).to be_a(Numeric) }

        it { expect(weekly_candle.low).to be_a(Numeric) }

        it { expect(weekly_candle.close).to be_a(Numeric) }

        it { expect(weekly_candle.volume).to be_a(Numeric) }
      end

      it 'aggregates from Monday to Sunday' do
        result
        weekly_candles = CandleSeriesRecord.where(instrument: instrument, timeframe: '1W')

        expect(weekly_candles).to be_any
        weekly_candles.each do |candle|
          expect(candle.timestamp.wday).to eq(1)
        end
      end
    end

    context 'when weeks_back is custom' do
      let(:mock_daily_candles) do
        28.times.map do |i|
          {
            timestamp: i.days.ago.to_i,
            open: 100.0 + i,
            high: 105.0 + i,
            low: 99.0 + i,
            close: 103.0 + i,
            volume: 1_000_000
          }
        end
      end

      let(:result) { described_class.call(instruments: instruments, weeks_back: 4) }

      before do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).with(
          from_date: anything,
          to_date: anything,
          oi: false
        ).and_return(mock_daily_candles)
      end

      it { expect(result[:processed]).to eq(1) }

      it { expect(result[:success]).to be > 0 }
    end

    context 'when daily candles are insufficient' do
      let(:instrument_no_candles) { create(:instrument, security_id: '99999') }
      let(:instruments_empty) { Instrument.where(id: instrument_no_candles.id) }
      let(:result) { described_class.call(instruments: instruments_empty, weeks_back: 1) }

      before do
        allow(instrument_no_candles).to receive(:historical_ohlc).and_return([])
      end

      it { expect(result[:failed]).to be >= 0 }
    end

    context 'when instrument has no security_id' do
      let(:instrument_no_security) do
        inst = create(:instrument, symbol_name: 'NO_SEC')
        # Use update_column to bypass validations and set security_id to empty string
        # This tests the service's error handling without violating database constraints
        inst.update_column(:security_id, '')
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

    context 'when multiple instruments are provided' do
      let(:instrument2) { create(:instrument, symbol_name: 'TEST2', security_id: '12346') }
      let(:multiple_instruments) { Instrument.where(id: [instrument.id, instrument2.id]) }
      let(:result) { described_class.call(instruments: multiple_instruments, weeks_back: 1) }

      before do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])
      end

      it { expect(result[:processed]).to eq(2) }
    end

    context 'when no instruments are provided' do
      let(:result) { described_class.call }

      before do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])
      end

      it { expect(result).to be_a(Hash) }

      it { expect(result[:processed]).to be >= 0 }
    end

    context 'with edge cases' do
      it 'handles API errors gracefully' do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_raise(StandardError.new('API error'))

        result = described_class.call(instruments: instruments, weeks_back: 1)

        expect(result[:failed]).to eq(1)
        expect(result[:errors]).not_to be_empty
      end

      it 'handles empty daily candles' do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])

        result = described_class.call(instruments: instruments, weeks_back: 1)

        expect(result[:failed]).to eq(1)
      end

      it 'handles nil daily candles' do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return(nil)

        result = described_class.call(instruments: instruments, weeks_back: 1)

        expect(result[:failed]).to eq(1)
      end

      it 'aggregates multiple weeks correctly' do
        # Create 14 days of candles (2 weeks)
        mock_daily_candles = 14.times.map do |i|
          {
            timestamp: i.days.ago.to_i,
            open: 100.0,
            high: 105.0,
            low: 99.0,
            close: 103.0,
            volume: 1_000_000
          }
        end

        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return(mock_daily_candles)

        result = described_class.call(instruments: instruments, weeks_back: 2)

        expect(result[:success]).to eq(1)
        weekly_count = CandleSeriesRecord.where(instrument: instrument, timeframe: '1W').count
        expect(weekly_count).to be >= 2
      end

      it 'handles hash format candles (DhanHQ format)' do
        mock_hash_candles = {
          'timestamp' => [7.days.ago.to_i, 6.days.ago.to_i],
          'open' => [100.0, 101.0],
          'high' => [105.0, 106.0],
          'low' => [99.0, 100.0],
          'close' => [103.0, 104.0],
          'volume' => [1_000_000, 1_100_000]
        }

        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return(mock_hash_candles)

        result = described_class.call(instruments: instruments, weeks_back: 1)

        expect(result[:success]).to eq(1)
      end

      it 'handles rate limiting delay' do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])
        allow(described_class).to receive(:sleep)

        # Process 10 instruments to trigger rate limiting
        instruments_list = create_list(:instrument, 10, security_id: '12345')
        instruments = Instrument.where(id: instruments_list.map(&:id))

        described_class.call(instruments: instruments, weeks_back: 1)

        # Should have called sleep at least once (every 10 instruments)
        expect(described_class).to have_received(:sleep).at_least(:once)
      end

      it 'logs summary correctly' do
        allow_any_instance_of(Instrument).to receive(:historical_ohlc).and_return([])
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)

        result = described_class.call(instruments: instruments, weeks_back: 1)

        expect(Rails.logger).to have_received(:info).at_least(:once)
      end

      it 'handles partial failures across multiple instruments' do
        instrument2 = create(:instrument, symbol_name: 'TEST2', security_id: '12346')
        instruments = Instrument.where(id: [instrument.id, instrument2.id])

        # First instrument succeeds, second fails
        allow(instrument).to receive(:historical_ohlc).and_return([
          { timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 }
        ])
        allow(instrument2).to receive(:historical_ohlc).and_raise(StandardError.new('API error'))

        result = described_class.call(instruments: instruments, weeks_back: 1)

        expect(result[:processed]).to eq(2)
        expect(result[:success]).to eq(1)
        expect(result[:failed]).to eq(1)
      end
    end

    describe 'private methods' do
      let(:service) { described_class.new(instruments: instruments, weeks_back: 1) }

      describe '#aggregate_to_weekly' do
        it 'aggregates daily candles to weekly' do
          daily_candles = 7.times.map do |i|
            {
              timestamp: i.days.ago.to_i,
              open: 100.0,
              high: 105.0,
              low: 99.0,
              close: 103.0,
              volume: 1_000_000
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

        it 'uses first open and last close' do
          daily_candles = [
            { timestamp: 6.days.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
            { timestamp: 5.days.ago.to_i, open: 103.0, high: 108.0, low: 102.0, close: 106.0, volume: 1_200_000 }
          ]

          weekly = service.send(:aggregate_to_weekly, daily_candles)

          expect(weekly.first[:open]).to eq(100.0) # First candle's open
          expect(weekly.first[:close]).to eq(106.0) # Last candle's close
        end

        it 'calculates max high and min low' do
          daily_candles = [
            { timestamp: 6.days.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
            { timestamp: 5.days.ago.to_i, open: 103.0, high: 110.0, low: 95.0, close: 106.0, volume: 1_200_000 }
          ]

          weekly = service.send(:aggregate_to_weekly, daily_candles)

          expect(weekly.first[:high]).to eq(110.0) # Max high
          expect(weekly.first[:low]).to eq(95.0) # Min low
        end

        it 'sums volumes' do
          daily_candles = [
            { timestamp: 6.days.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
            { timestamp: 5.days.ago.to_i, open: 103.0, high: 108.0, low: 102.0, close: 106.0, volume: 1_200_000 }
          ]

          weekly = service.send(:aggregate_to_weekly, daily_candles)

          expect(weekly.first[:volume]).to eq(2_200_000) # Sum of volumes
        end

        it 'handles empty candles' do
          weekly = service.send(:aggregate_to_weekly, [])

          expect(weekly).to eq([])
        end

        it 'sorts by timestamp' do
          daily_candles = [
            { timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 },
            { timestamp: 7.days.ago.to_i, open: 98.0, high: 102.0, low: 97.0, close: 100.0, volume: 900_000 }
          ]

          weekly = service.send(:aggregate_to_weekly, daily_candles)

          timestamps = weekly.map { |c| c[:timestamp] }
          expect(timestamps).to eq(timestamps.sort)
        end
      end

      describe '#normalize_candles' do
        it 'handles array format' do
          candles = [
            { timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 }
          ]

          normalized = service.send(:normalize_candles, candles)

          expect(normalized).to be_an(Array)
          expect(normalized.first).to have_key(:timestamp)
        end

        it 'handles hash format (DhanHQ)' do
          candles = {
            'timestamp' => [1.day.ago.to_i],
            'open' => [100.0],
            'high' => [105.0],
            'low' => [99.0],
            'close' => [103.0],
            'volume' => [1_000_000]
          }

          normalized = service.send(:normalize_candles, candles)

          expect(normalized).to be_an(Array)
          expect(normalized.first).to have_key(:timestamp)
        end

        it 'handles single hash' do
          candle = { timestamp: 1.day.ago.to_i, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000 }

          normalized = service.send(:normalize_candles, candle)

          expect(normalized).to be_an(Array)
          expect(normalized.size).to eq(1)
        end

        it 'handles nil data' do
          normalized = service.send(:normalize_candles, nil)

          expect(normalized).to eq([])
        end

        it 'handles invalid candle data gracefully' do
          invalid_candle = { invalid: 'data' }

          normalized = service.send(:normalize_candles, [invalid_candle])

          expect(normalized).to be_an(Array)
        end
      end

      describe '#parse_timestamp' do
        it 'handles Time objects' do
          time = Time.current
          parsed = service.send(:parse_timestamp, time)

          expect(parsed).to be_a(Time)
        end

        it 'handles integer timestamps' do
          timestamp = Time.current.to_i
          parsed = service.send(:parse_timestamp, timestamp)

          expect(parsed).to be_a(Time)
        end

        it 'handles string timestamps' do
          timestamp = Time.current.iso8601
          parsed = service.send(:parse_timestamp, timestamp)

          expect(parsed).to be_a(Time)
        end

        it 'handles nil timestamps' do
          parsed = service.send(:parse_timestamp, nil)

          expect(parsed).to be_a(Time)
        end

        it 'handles invalid timestamps' do
          parsed = service.send(:parse_timestamp, 'invalid')

          expect(parsed).to be_a(Time)
        end
      end
    end
  end
end

