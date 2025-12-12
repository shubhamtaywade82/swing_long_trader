# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::LongTerm::Evaluator, type: :service do
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
      let(:daily_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: '1D') }
      let(:weekly_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: '1W') }

      before do
        200.times { daily_series.add_candle(create(:candle)) }
        52.times { weekly_series.add_candle(create(:candle)) }

        allow(instrument).to receive(:load_daily_candles).and_return(daily_series)
        allow(instrument).to receive(:load_weekly_candles).and_return(weekly_series)
        allow(AlgoConfig).to receive(:fetch).and_return({})
      end

      it 'loads candles and builds signal' do
        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be true
        expect(result[:signal]).to be_present
        expect(result[:signal][:direction]).to eq(:long)
      end

      it 'includes metadata' do
        result = described_class.new(candidate: candidate).call

        expect(result[:metadata]).to be_present
        expect(result[:metadata][:daily_candles]).to eq(200)
        expect(result[:metadata][:weekly_candles]).to eq(52)
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

    context 'when candles fail to load' do
      before do
        allow(instrument).to receive(:load_daily_candles).and_return(nil)
      end

      it 'returns error' do
        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Failed to load candles')
      end
    end

    context 'when entry conditions fail' do
      let(:daily_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: '1D') }
      let(:weekly_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: '1W') }

      before do
        200.times { daily_series.add_candle(create(:candle)) }
        52.times { weekly_series.add_candle(create(:candle)) }

        allow(instrument).to receive(:load_daily_candles).and_return(daily_series)
        allow(instrument).to receive(:load_weekly_candles).and_return(weekly_series)
        allow(AlgoConfig).to receive(:fetch).and_return(
          long_term_trading: {
            strategy: {
              entry_conditions: {
                require_weekly_trend: true
              }
            }
          }
        )
        allow(daily_series).to receive(:ema).and_return(100.0)
        allow(weekly_series).to receive(:ema).and_return(95.0) # EMA20 < EMA50 (fails)
      end

      it 'returns error' do
        result = described_class.new(candidate: candidate).call

        expect(result[:success]).to be false
        expect(result[:error]).to include('Weekly EMA not aligned')
      end
    end
  end
end

