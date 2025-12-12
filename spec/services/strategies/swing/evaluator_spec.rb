# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Swing::Evaluator, type: :service do
  let(:instrument) { create(:instrument) }
  let(:candidate) do
    {
      instrument_id: instrument.id,
      symbol: instrument.symbol_name,
      score: 85
    }
  end

  describe '.call' do
    it 'delegates to instance method' do
      allow_any_instance_of(described_class).to receive(:call).and_return({ success: true })

      described_class.call(candidate)

      expect_any_instance_of(described_class).to have_received(:call)
    end
  end

  describe '#call' do
    context 'when candidate is valid' do
      before do
        allow(instrument).to receive(:load_daily_candles).and_return(
          create(:candle_series, candles: create_list(:candle, 100))
        )
        allow(instrument).to receive(:load_weekly_candles).and_return(
          create(:candle_series, candles: create_list(:candle, 52))
        )
        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          { success: true, signal: { direction: 'long' } }
        )
      end

      it 'loads candles and runs engine' do
        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be true
        expect(instrument).to have_received(:load_daily_candles).with(limit: 100)
        expect(instrument).to have_received(:load_weekly_candles).with(limit: 52)
        expect(Strategies::Swing::Engine).to have_received(:call)
      end
    end

    context 'when candidate is invalid' do
      it 'returns error' do
        result = described_class.new(candidate: nil).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid candidate')
      end
    end

    context 'when instrument is not found' do
      let(:candidate) { { instrument_id: 99999, symbol: 'INVALID' } }

      it 'returns error' do
        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Instrument not found')
      end
    end

    context 'when daily candles fail to load' do
      before do
        allow(instrument).to receive(:load_daily_candles).and_return(nil)
      end

      it 'returns error' do
        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Failed to load daily candles')
      end
    end
  end
end

