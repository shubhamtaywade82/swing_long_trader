# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Screeners::LongtermScreener, type: :service do
  let(:instrument) { create(:instrument) }

  describe '.call' do
    it 'delegates to instance method' do
      allow_any_instance_of(described_class).to receive(:call).and_return([])

      described_class.call

      expect_any_instance_of(described_class).to have_received(:call)
    end
  end

  describe '#call' do
    context 'when instruments are provided' do
      let(:instruments) { Instrument.where(id: instrument.id) }

      before do
        allow(instrument).to receive(:has_candles?).and_return(true)
        allow(instrument).to receive(:load_daily_candles).and_return(
          create(:candle_series, candles: create_list(:candle, 150))
        )
        allow(instrument).to receive(:load_weekly_candles).and_return(
          create(:candle_series, candles: create_list(:candle, 30))
        )
        allow_any_instance_of(described_class).to receive(:calculate_indicators).and_return(
          { rsi: 65, ema20: 100.0, trend: 'bullish' }
        )
        allow_any_instance_of(described_class).to receive(:calculate_score).and_return(85.0)
      end

      it 'analyzes provided instruments' do
        result = described_class.new(instruments: instruments, limit: 10).call

        expect(result).to be_an(Array)
      end
    end

    context 'when no instruments provided' do
      before do
        allow(Instrument).to receive(:where).and_return(Instrument.none)
      end

      it 'loads from universe file' do
        universe_file = Rails.root.join('config/universe/master_universe.yml')
        allow(File).to receive(:exist?).with(universe_file).and_return(false)
        allow(Instrument).to receive(:where).with(instrument_type: ['EQUITY', 'INDEX']).and_return(Instrument.none)

        result = described_class.new.call

        expect(result).to be_an(Array)
      end
    end

    context 'when instrument lacks candles' do
      let(:instruments) { Instrument.where(id: instrument.id) }

      before do
        allow(instrument).to receive(:has_candles?).and_return(false)
      end

      it 'skips instrument' do
        result = described_class.new(instruments: instruments, limit: 10).call

        expect(result).to be_empty
      end
    end

    context 'when instrument has insufficient data' do
      let(:instruments) { Instrument.where(id: instrument.id) }

      before do
        allow(instrument).to receive(:has_candles?).and_return(true)
        allow(instrument).to receive(:load_daily_candles).and_return(
          create(:candle_series, candles: create_list(:candle, 50)) # Less than 100
        )
      end

      it 'skips instrument' do
        result = described_class.new(instruments: instruments, limit: 10).call

        expect(result).to be_empty
      end
    end

    context 'when limit is specified' do
      let(:instruments) { create_list(:instrument, 5) }

      before do
        instruments.each do |inst|
          allow(inst).to receive(:has_candles?).and_return(true)
          allow(inst).to receive(:load_daily_candles).and_return(
            create(:candle_series, candles: create_list(:candle, 150))
          )
          allow(inst).to receive(:load_weekly_candles).and_return(
            create(:candle_series, candles: create_list(:candle, 30))
          )
        end
        allow_any_instance_of(described_class).to receive(:calculate_indicators).and_return(
          { rsi: 65, ema20: 100.0 }
        )
        allow_any_instance_of(described_class).to receive(:calculate_score).and_return(85.0)
      end

      it 'returns only top N candidates' do
        result = described_class.new(instruments: Instrument.where(id: instruments.map(&:id)), limit: 3).call

        expect(result.size).to be <= 3
      end
    end
  end
end

