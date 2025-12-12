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
  end
end

