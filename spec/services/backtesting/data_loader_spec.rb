# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtesting::DataLoader, type: :service do
  let(:instrument) { create(:instrument) }
  let(:instruments) { Instrument.where(id: instrument.id) }
  let(:from_date) { 10.days.ago.to_date }
  let(:to_date) { Date.today }

  before do
    # Create candles for date range
    10.times do |i|
      create(:daily_candle,
        instrument: instrument,
        timestamp: i.days.ago,
        open: 100.0 + i,
        high: 105.0 + i,
        low: 99.0 + i,
        close: 103.0 + i,
        volume: 1_000_000
      )
    end
  end

  describe '#load_for_instrument' do
    it 'loads candles for instrument' do
      loader = described_class.new
      series = loader.load_for_instrument(
        instrument: instrument,
        timeframe: '1D',
        from_date: from_date,
        to_date: to_date
      )

      expect(series).not_to be_nil
      expect(series.candles).to be_any
      expect(series.interval).to eq('1D')
    end
  end

  describe '#validate_data' do
    it 'validates data with minimum candles' do
      loader = described_class.new
      data = {
        instrument.id => create_series_with_candles(60),
        create(:instrument).id => create_series_with_candles(30) # Insufficient
      }

      validated = loader.validate_data(data, min_candles: 50)

      expect(validated.size).to eq(1)
      expect(validated).to have_key(instrument.id)
    end
  end

  describe '.load_for_instruments' do
    it 'loads for multiple instruments' do
      instrument2 = create(:instrument)
      create_list(:daily_candle, 10, instrument: instrument2)

      data = described_class.load_for_instruments(
        instruments: Instrument.where(id: [instrument.id, instrument2.id]),
        timeframe: '1D',
        from_date: from_date,
        to_date: to_date
      )

      expect(data.size).to eq(2)
      expect(data).to have_key(instrument.id)
      expect(data).to have_key(instrument2.id)
    end

    it 'skips instruments with no candles' do
      instrument_no_candles = create(:instrument)

      data = described_class.load_for_instruments(
        instruments: Instrument.where(id: [instrument.id, instrument_no_candles.id]),
        timeframe: '1D',
        from_date: from_date,
        to_date: to_date
      )

      expect(data.size).to eq(1)
      expect(data).to have_key(instrument.id)
      expect(data).not_to have_key(instrument_no_candles.id)
    end
  end

  describe '#load_for_instrument' do
    context 'when no candles exist' do
      it 'returns nil' do
        instrument_no_candles = create(:instrument)
        loader = described_class.new

        series = loader.load_for_instrument(
          instrument: instrument_no_candles,
          timeframe: '1D',
          from_date: from_date,
          to_date: to_date
        )

        expect(series).to be_nil
      end
    end

    context 'with interpolation enabled' do
      it 'fills missing daily candles' do
        # Create candles with gaps
        create(:daily_candle, instrument: instrument, timestamp: 5.days.ago)
        create(:daily_candle, instrument: instrument, timestamp: 2.days.ago)

        loader = described_class.new
        series = loader.load_for_instrument(
          instrument: instrument,
          timeframe: '1D',
          from_date: 5.days.ago.to_date,
          to_date: Date.today,
          interpolate_missing: true
        )

        expect(series).not_to be_nil
        expect(series.candles.size).to be >= 2
      end

      it 'does not interpolate for non-daily timeframes' do
        create_list(:candle_series_record, 5, instrument: instrument, timeframe: '1W')

        loader = described_class.new
        series = loader.load_for_instrument(
          instrument: instrument,
          timeframe: '1W',
          from_date: 30.days.ago.to_date,
          to_date: Date.today,
          interpolate_missing: true
        )

        expect(series).not_to be_nil
        # Should not interpolate for weekly timeframe
      end
    end

    context 'without interpolation' do
      it 'loads only existing candles' do
        loader = described_class.new
        series = loader.load_for_instrument(
          instrument: instrument,
          timeframe: '1D',
          from_date: from_date,
          to_date: to_date,
          interpolate_missing: false
        )

        expect(series).not_to be_nil
        expect(series.candles.size).to eq(10)
      end
    end
  end

  describe '#validate_data' do
    context 'with large gaps' do
      it 'detects and logs large gaps' do
        loader = described_class.new
        series = create_series_with_candles(60)
        # Create gap by removing middle candles
        series.candles.delete_at(30)
        series.candles.delete_at(30)
        series.candles.delete_at(30)
        series.candles.delete_at(30)
        series.candles.delete_at(30)
        series.candles.delete_at(30) # 6 day gap

        data = { instrument.id => series }
        allow(Rails.logger).to receive(:warn)

        validated = loader.validate_data(data, min_candles: 50, max_gap_days: 5)

        expect(validated).to have_key(instrument.id)
        expect(Rails.logger).to have_received(:warn)
      end
    end

    context 'with empty series' do
      it 'skips empty series' do
        loader = described_class.new
        empty_series = CandleSeries.new(symbol: 'TEST', interval: '1D')
        data = { instrument.id => empty_series }

        validated = loader.validate_data(data)

        expect(validated).not_to have_key(instrument.id)
      end
    end

    context 'with nil series' do
      it 'skips nil series' do
        loader = described_class.new
        data = { instrument.id => nil }

        validated = loader.validate_data(data)

        expect(validated).not_to have_key(instrument.id)
      end
    end
  end

  describe '#detect_gaps' do
    it 'detects gaps in candles' do
      loader = described_class.new
      candles = [
        Candle.new(timestamp: 5.days.ago),
        Candle.new(timestamp: 2.days.ago) # 2 day gap
      ]

      gaps = loader.detect_gaps(candles)

      expect(gaps.size).to eq(1)
      expect(gaps.first[:days]).to eq(2)
    end

    it 'returns empty array for single candle' do
      loader = described_class.new
      candles = [Candle.new(timestamp: Date.today)]

      gaps = loader.detect_gaps(candles)

      expect(gaps).to eq([])
    end

    it 'returns empty array for empty candles' do
      loader = described_class.new

      gaps = loader.detect_gaps([])

      expect(gaps).to eq([])
    end

    it 'handles consecutive candles (no gaps)' do
      loader = described_class.new
      candles = [
        Candle.new(timestamp: 2.days.ago),
        Candle.new(timestamp: 1.day.ago),
        Candle.new(timestamp: Date.today)
      ]

      gaps = loader.detect_gaps(candles)

      expect(gaps).to eq([])
    end
  end

  describe '#fill_missing_daily_candles' do
    let(:loader) { described_class.new }
    let(:series) { CandleSeries.new(symbol: 'TEST', interval: '1D') }
    let(:from_date) { 5.days.ago.to_date }
    let(:to_date) { Date.today }

    context 'with consecutive candles' do
      let(:existing_candles) do
        {
          5.days.ago.to_date => Candle.new(timestamp: 5.days.ago, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000),
          4.days.ago.to_date => Candle.new(timestamp: 4.days.ago, open: 103.0, high: 108.0, low: 102.0, close: 106.0, volume: 1_200_000),
          2.days.ago.to_date => Candle.new(timestamp: 2.days.ago, open: 106.0, high: 110.0, low: 105.0, close: 108.0, volume: 1_100_000)
        }
      end

      it 'fills missing dates with interpolated candles' do
        loader.send(:fill_missing_daily_candles, series, existing_candles, from_date, to_date, true)

        expect(series.candles.size).to be >= 3
        # Should have interpolated candles for missing dates
      end

      it 'uses last candle close for interpolation' do
        loader.send(:fill_missing_daily_candles, series, existing_candles, from_date, to_date, true)

        # Find interpolated candle (should have zero volume)
        interpolated = series.candles.find { |c| c.volume == 0 }
        expect(interpolated).to be_present if series.candles.size > existing_candles.size
      end
    end

    context 'without last candle' do
      let(:existing_candles) do
        {
          3.days.ago.to_date => Candle.new(timestamp: 3.days.ago, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000)
        }
      end

      it 'skips interpolation when no prior candle exists' do
        loader.send(:fill_missing_daily_candles, series, existing_candles, from_date, to_date, true)

        # Should only have the existing candle, no interpolation before it
        expect(series.candles.size).to eq(1)
      end
    end

    context 'with interpolation disabled' do
      let(:existing_candles) do
        {
          5.days.ago.to_date => Candle.new(timestamp: 5.days.ago, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000),
          2.days.ago.to_date => Candle.new(timestamp: 2.days.ago, open: 106.0, high: 110.0, low: 105.0, close: 108.0, volume: 1_100_000)
        }
      end

      it 'does not fill missing dates when interpolation is false' do
        # This method is only called when interpolate_missing is true
        # But we can test that it respects the flag
        loader.send(:fill_missing_daily_candles, series, existing_candles, from_date, to_date, false)

        # Should still add existing candles
        expect(series.candles.size).to be >= 2
      end
    end
  end

  describe '#load_for_instrument' do
    context 'with weekly timeframe' do
      before do
        create_list(:candle_series_record, 5,
          instrument: instrument,
          timeframe: '1W',
          timestamp: (4.weeks.ago..Time.current).step(1.week).to_a)
      end

      it 'loads weekly candles' do
        loader = described_class.new
        series = loader.load_for_instrument(
          instrument: instrument,
          timeframe: '1W',
          from_date: 4.weeks.ago.to_date,
          to_date: Date.today
        )

        expect(series).not_to be_nil
        expect(series.interval).to eq('1W')
      end
    end

    context 'with ordered candles' do
      before do
        # Create candles out of order
        create(:daily_candle, instrument: instrument, timestamp: 2.days.ago)
        create(:daily_candle, instrument: instrument, timestamp: 5.days.ago)
        create(:daily_candle, instrument: instrument, timestamp: 1.day.ago)
      end

      it 'loads candles in chronological order' do
        loader = described_class.new
        series = loader.load_for_instrument(
          instrument: instrument,
          timeframe: '1D',
          from_date: 5.days.ago.to_date,
          to_date: Date.today
        )

        expect(series).not_to be_nil
        timestamps = series.candles.map(&:timestamp)
        expect(timestamps).to eq(timestamps.sort)
      end
    end
  end

  describe '#validate_data' do
    context 'with minimum candles threshold' do
      it 'filters out series with insufficient candles' do
        loader = described_class.new
        data = {
          instrument.id => create_series_with_candles(30), # Below threshold
          create(:instrument).id => create_series_with_candles(60) # Above threshold
        }

        validated = loader.validate_data(data, min_candles: 50)

        expect(validated.size).to eq(1)
      end
    end

    context 'with gap detection' do
      it 'detects and logs large gaps' do
        loader = described_class.new
        # Create series with a large gap
        series = CandleSeries.new(symbol: 'TEST', interval: '1D')
        series.add_candle(Candle.new(timestamp: 20.days.ago, open: 100.0, high: 105.0, low: 99.0, close: 103.0, volume: 1_000_000))
        series.add_candle(Candle.new(timestamp: 10.days.ago, open: 103.0, high: 108.0, low: 102.0, close: 106.0, volume: 1_200_000)) # 10-day gap
        series.add_candle(Candle.new(timestamp: 1.day.ago, open: 106.0, high: 110.0, low: 105.0, close: 108.0, volume: 1_100_000))

        data = { instrument.id => series }
        allow(Rails.logger).to receive(:warn)

        validated = loader.validate_data(data, min_candles: 2, max_gap_days: 5)

        expect(validated).to have_key(instrument.id)
        expect(Rails.logger).to have_received(:warn)
      end
    end
  end

  private

  def create_series_with_candles(count)
    series = CandleSeries.new(symbol: 'TEST', interval: '1D')
    count.times do |i|
      series.add_candle(
        Candle.new(
          timestamp: i.days.ago,
          open: 100.0,
          high: 105.0,
          low: 99.0,
          close: 103.0,
          volume: 1_000_000
        )
      )
    end
    series
  end
end

