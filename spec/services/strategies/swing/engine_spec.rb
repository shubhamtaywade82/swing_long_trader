# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Swing::Engine, type: :service do
  let(:instrument) { create(:instrument) }
  let(:daily_series) { create(:candle_series, symbol: instrument.symbol_name, interval: '1D') }
  let(:weekly_series) { create(:candle_series, symbol: instrument.symbol_name, interval: '1W') }

  before do
    # Add sufficient candles
    60.times do |i|
      daily_series.add_candle(create(:candle, timestamp: i.days.ago))
    end
  end

  describe '.call' do
    it 'delegates to instance method' do
      allow_any_instance_of(described_class).to receive(:call).and_return({ success: true })

      described_class.call(
        instrument: instrument,
        daily_series: daily_series
      )

      expect_any_instance_of(described_class).to have_received(:call)
    end
  end

  describe '#call' do
    context 'when inputs are valid' do
      before do
        allow(Strategies::Swing::SignalBuilder).to receive(:call).and_return(
          {
            direction: 'long',
            entry_price: 100.0,
            confidence: 75,
            sl: 95.0,
            tp: 110.0
          }
        )
        allow(Smc::StructureValidator).to receive(:validate).and_return({ valid: true })
      end

      it 'returns success with signal' do
        result = described_class.new(
          instrument: instrument,
          daily_series: daily_series
        ).call

        expect(result[:success]).to be true
        expect(result[:signal]).to be_present
      end

      it 'includes metadata' do
        result = described_class.new(
          instrument: instrument,
          daily_series: daily_series
        ).call

        expect(result[:metadata]).to be_present
        expect(result[:metadata][:evaluated_at]).to be_present
        expect(result[:metadata][:candles_analyzed]).to eq(60)
      end
    end

    context 'when instrument is invalid' do
      it 'returns error' do
        result = described_class.new(
          instrument: nil,
          daily_series: daily_series
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid instrument')
      end
    end

    context 'when insufficient candles' do
      let(:small_series) { create(:candle_series) }

      before do
        30.times { small_series.add_candle(create(:candle)) }
      end

      it 'returns error' do
        result = described_class.new(
          instrument: instrument,
          daily_series: small_series
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Insufficient daily candles')
      end
    end

    context 'when entry conditions fail' do
      before do
        allow_any_instance_of(described_class).to receive(:check_entry_conditions).and_return(
          { allowed: false, error: 'Trend alignment failed' }
        )
      end

      it 'returns error' do
        result = described_class.new(
          instrument: instrument,
          daily_series: daily_series,
          config: { entry_conditions: { require_trend_alignment: true } }
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Trend alignment failed')
      end
    end

    context 'when SMC validation fails' do
      before do
        allow(Smc::StructureValidator).to receive(:validate).and_return(
          { valid: false, reasons: ['No BOS detected'] }
        )
        allow(Strategies::Swing::SignalBuilder).to receive(:call).and_return(
          { direction: 'long', entry_price: 100.0, confidence: 75 }
        )
      end

      it 'returns error' do
        result = described_class.new(
          instrument: instrument,
          daily_series: daily_series
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to include('SMC validation failed')
      end
    end

    context 'when confidence is too low' do
      before do
        allow(Strategies::Swing::SignalBuilder).to receive(:call).and_return(
          { direction: 'long', entry_price: 100.0, confidence: 50 }
        )
        allow(Smc::StructureValidator).to receive(:validate).and_return({ valid: true })
      end

      it 'returns error' do
        result = described_class.new(
          instrument: instrument,
          daily_series: daily_series,
          config: { min_confidence: 0.7 }
        ).call

        expect(result[:success]).to be false
        expect(result[:error]).to include('Confidence too low')
      end
    end

    context '#check_entry_conditions' do
      let(:engine) { described_class.new(instrument: instrument, daily_series: daily_series) }

      it 'allows entry when no conditions required' do
        result = engine.send(:check_entry_conditions)

        expect(result[:allowed]).to be true
      end

      it 'requires trend alignment when configured' do
        allow(engine).to receive(:check_trend_alignment).and_return(false)

        result = engine.send(:check_entry_conditions, config: { entry_conditions: { require_trend_alignment: true } })

        expect(result[:allowed]).to be false
        expect(result[:error]).to eq('Trend alignment failed')
      end

      it 'requires volume confirmation when configured' do
        allow(engine).to receive(:check_volume_confirmation).and_return(false)

        result = engine.send(:check_entry_conditions, config: { entry_conditions: { require_volume_confirmation: true } })

        expect(result[:allowed]).to be false
        expect(result[:error]).to eq('Volume confirmation failed')
      end
    end

    context '#check_trend_alignment' do
      let(:engine) { described_class.new(instrument: instrument, daily_series: daily_series) }

      before do
        allow(engine).to receive(:calculate_indicators).and_return({
          ema20: 100.0,
          ema50: 95.0,
          ema200: 90.0,
          supertrend: { direction: :bullish }
        })
      end

      it 'validates EMA alignment' do
        result = engine.send(:check_trend_alignment, config: {
          trend_filters: { use_ema20: true, use_ema50: true }
        })

        expect(result).to be true
      end

      it 'validates EMA200 alignment' do
        result = engine.send(:check_trend_alignment, config: {
          trend_filters: { use_ema200: true }
        })

        expect(result).to be true
      end

      it 'returns false when EMA20 < EMA50' do
        allow(engine).to receive(:calculate_indicators).and_return({
          ema20: 95.0,
          ema50: 100.0,
          supertrend: { direction: :bullish }
        })

        result = engine.send(:check_trend_alignment, config: {
          trend_filters: { use_ema20: true, use_ema50: true }
        })

        expect(result).to be false
      end

      it 'returns false when supertrend is not bullish' do
        allow(engine).to receive(:calculate_indicators).and_return({
          ema20: 100.0,
          ema50: 95.0,
          supertrend: { direction: :bearish }
        })

        result = engine.send(:check_trend_alignment)

        expect(result).to be false
      end
    end

    context '#check_volume_confirmation' do
      let(:engine) { described_class.new(instrument: instrument, daily_series: daily_series) }

      it 'returns true for insufficient candles' do
        small_series = CandleSeries.new(symbol: 'TEST', interval: '1D')
        10.times { small_series.add_candle(create(:candle, volume: 1_000_000)) }
        engine = described_class.new(instrument: instrument, daily_series: small_series)

        result = engine.send(:check_volume_confirmation, 1.5)

        expect(result).to be true
      end

      it 'validates volume spike' do
        # Create series with volume spike
        volumes = Array.new(20, 1_000_000) + [3_000_000] # Latest volume is 3x average
        volumes.each_with_index do |vol, i|
          daily_series.candles[i]&.volume = vol if daily_series.candles[i]
        end

        result = engine.send(:check_volume_confirmation, 1.5)

        expect(result).to be true
      end

      it 'returns false when volume spike is insufficient' do
        # Create series with low volume
        volumes = Array.new(21, 1_000_000) # All same volume, no spike
        volumes.each_with_index do |vol, i|
          daily_series.candles[i]&.volume = vol if daily_series.candles[i]
        end

        result = engine.send(:check_volume_confirmation, 2.0)

        expect(result).to be false
      end
    end
  end
end

