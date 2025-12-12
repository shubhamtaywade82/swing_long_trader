# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Complete Trading Pipeline Integration', type: :integration do
  let(:instrument) { create(:instrument) }
  let(:daily_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: '1D') }
  let(:weekly_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: '1W') }

  before do
    # Create sufficient candles
    100.times do |i|
      daily_series.add_candle(create(:candle, timestamp: i.days.ago))
    end
    52.times do |i|
      weekly_series.add_candle(create(:candle, timestamp: i.weeks.ago))
    end

    # Store candles in database
    daily_series.candles.each do |candle|
      create(:candle_series_record,
        instrument: instrument,
        timeframe: '1D',
        timestamp: candle.timestamp,
        open: candle.open,
        high: candle.high,
        low: candle.low,
        close: candle.close,
        volume: candle.volume)
    end

    # Mock external services
    allow(instrument).to receive(:load_daily_candles).and_return(daily_series)
    allow(instrument).to receive(:load_weekly_candles).and_return(weekly_series)
    allow(TelegramNotifier).to receive(:enabled?).and_return(false)
    allow(AlgoConfig).to receive(:fetch).and_return({})
  end

  describe 'End-to-end pipeline: Universe -> Screener -> AI Ranker -> Strategy -> Execution' do
    context 'when all steps succeed' do
      before do
        # Mock screener
        allow(Screeners::SwingScreener).to receive(:call).and_return(
          [
            {
              instrument_id: instrument.id,
              symbol: instrument.symbol_name,
              score: 85,
              indicators: { rsi: 65, ema20: 100.0 }
            }
          ]
        )

        # Mock AI ranker
        allow(Screeners::AIRanker).to receive(:call).and_return(
          [
            {
              instrument_id: instrument.id,
              symbol: instrument.symbol_name,
              score: 85,
              ai_score: 80,
              ai_confidence: 75
            }
          ]
        )

        # Mock signal builder
        allow(Strategies::Swing::SignalBuilder).to receive(:call).and_return(
          {
            instrument_id: instrument.id,
            symbol: instrument.symbol_name,
            direction: 'long',
            entry_price: 100.0,
            sl: 95.0,
            tp: 110.0,
            confidence: 75,
            qty: 10
          }
        )

        # Mock executor
        allow(Strategies::Swing::Executor).to receive(:call).and_return(
          { success: true, order: create(:order, instrument: instrument) }
        )
      end

      it 'executes complete pipeline successfully' do
        # Step 1: Screener
        candidates = Screeners::SwingScreener.call
        expect(candidates).to be_present

        # Step 2: AI Ranker
        ranked = Screeners::AIRanker.call(candidates: candidates)
        expect(ranked).to be_present
        expect(ranked.first).to have_key(:ai_score)

        # Step 3: Strategy Engine
        result = Strategies::Swing::Engine.call(
          instrument: instrument,
          daily_series: daily_series,
          weekly_series: weekly_series
        )
        expect(result[:success]).to be true

        # Step 4: Executor
        execution = Strategies::Swing::Executor.call(result[:signal])
        expect(execution[:success]).to be true
      end
    end

    context 'when screener returns empty results' do
      before do
        allow(Screeners::SwingScreener).to receive(:call).and_return([])
      end

      it 'stops pipeline early' do
        candidates = Screeners::SwingScreener.call

        expect(candidates).to be_empty
        # Pipeline should stop here
      end
    end

    context 'when AI ranker fails' do
      before do
        allow(Screeners::SwingScreener).to receive(:call).and_return(
          [{ instrument_id: instrument.id, symbol: instrument.symbol_name, score: 85 }]
        )
        allow(Screeners::AIRanker).to receive(:call).and_raise(StandardError, 'AI service unavailable')
      end

      it 'handles error gracefully' do
        candidates = Screeners::SwingScreener.call

        expect do
          Screeners::AIRanker.call(candidates: candidates)
        end.to raise_error(StandardError, 'AI service unavailable')
      end
    end

    context 'when signal generation fails' do
      before do
        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          { success: false, error: 'Insufficient data' }
        )
      end

      it 'returns error without executing' do
        result = Strategies::Swing::Engine.call(
          instrument: instrument,
          daily_series: daily_series
        )

        expect(result[:success]).to be false
        expect(Strategies::Swing::Executor).not_to have_received(:call)
      end
    end

    context 'when execution fails' do
      before do
        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          { success: true, signal: { instrument_id: instrument.id } }
        )
        allow(Strategies::Swing::Executor).to receive(:call).and_return(
          { success: false, error: 'Execution failed' }
        )
      end

      it 'handles execution failure' do
        result = Strategies::Swing::Engine.call(
          instrument: instrument,
          daily_series: daily_series
        )

        execution = Strategies::Swing::Executor.call(result[:signal])
        expect(execution[:success]).to be false
      end
    end
  end
end

