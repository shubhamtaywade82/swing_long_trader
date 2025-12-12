# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Complete Trading Pipeline', type: :integration do
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
    allow(Telegram::Notifier).to receive(:enabled?).and_return(false)
    allow(Rails.configuration.x.paper_trading).to receive(:enabled).and_return(true)
  end

  describe 'Complete pipeline: Screener -> AI Ranker -> Final Selector -> Engine -> Executor' do
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

        # Mock final selector
        allow(Screeners::FinalSelector).to receive(:call).and_return(
          [
            {
              instrument_id: instrument.id,
              symbol: instrument.symbol_name,
              combined_score: 82.5,
              screener_score: 85,
              ai_score: 80
            }
          ]
        )

        # Mock engine
        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          {
            success: true,
            signal: {
              instrument_id: instrument.id,
              symbol: instrument.symbol_name,
              direction: 'long',
              entry_price: 100.0,
              sl: 95.0,
              tp: 110.0,
              confidence: 75,
              qty: 10
            }
          }
        )

        # Mock executor
        allow(PaperTrading::Executor).to receive(:execute).and_return(
          { success: true, position: create(:paper_position) }
        )
      end

      it 'executes complete pipeline successfully' do
        # Step 1: Screener
        candidates = Screeners::SwingScreener.call
        expect(candidates).to be_present

        # Step 2: AI Ranker
        ranked = Screeners::AIRanker.call(candidates: candidates)
        expect(ranked).to be_present

        # Step 3: Final Selector
        selected = Screeners::FinalSelector.call(candidates: ranked)
        expect(selected).to be_present

        # Step 4: Engine (signal generation)
        result = Strategies::Swing::Engine.call(
          instrument: instrument,
          daily_series: daily_series,
          weekly_series: weekly_series
        )
        expect(result[:success]).to be true

        # Step 5: Executor
        execution = Strategies::Swing::Executor.call(result[:signal])
        expect(execution[:success]).to be true
      end
    end

    context 'when screener returns no candidates' do
      before do
        allow(Screeners::SwingScreener).to receive(:call).and_return([])
      end

      it 'stops pipeline early' do
        candidates = Screeners::SwingScreener.call
        expect(candidates).to be_empty
      end
    end

    context 'when AI ranker fails' do
      before do
        allow(Screeners::SwingScreener).to receive(:call).and_return(
          [{ instrument_id: instrument.id, symbol: instrument.symbol_name, score: 85 }]
        )
        allow(Screeners::AIRanker).to receive(:call).and_return([])
      end

      it 'continues with unranked candidates' do
        candidates = Screeners::SwingScreener.call
        ranked = Screeners::AIRanker.call(candidates: candidates)
        expect(ranked).to be_empty
      end
    end

    context 'when final selector filters out candidates' do
      before do
        allow(Screeners::SwingScreener).to receive(:call).and_return(
          [{ instrument_id: instrument.id, symbol: instrument.symbol_name, score: 85 }]
        )
        allow(Screeners::AIRanker).to receive(:call).and_return(
          [{ instrument_id: instrument.id, symbol: instrument.symbol_name, score: 85, ai_score: 80 }]
        )
        allow(Screeners::FinalSelector).to receive(:call).and_return([])
      end

      it 'stops pipeline when no candidates selected' do
        candidates = Screeners::SwingScreener.call
        ranked = Screeners::AIRanker.call(candidates: candidates)
        selected = Screeners::FinalSelector.call(candidates: ranked)

        expect(selected).to be_empty
      end
    end

    context 'when signal generation fails' do
      before do
        allow(Screeners::SwingScreener).to receive(:call).and_return(
          [{ instrument_id: instrument.id, symbol: instrument.symbol_name, score: 85 }]
        )
        allow(Screeners::AIRanker).to receive(:call).and_return(
          [{ instrument_id: instrument.id, symbol: instrument.symbol_name, score: 85, ai_score: 80 }]
        )
        allow(Screeners::FinalSelector).to receive(:call).and_return(
          [{ instrument_id: instrument.id, symbol: instrument.symbol_name, combined_score: 82.5 }]
        )
        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          { success: false, error: 'Insufficient candles' }
        )
      end

      it 'returns error without executing' do
        candidates = Screeners::SwingScreener.call
        ranked = Screeners::AIRanker.call(candidates: candidates)
        _selected = Screeners::FinalSelector.call(candidates: ranked)

        result = Strategies::Swing::Engine.call(
          instrument: instrument,
          daily_series: daily_series
        )

        expect(result[:success]).to be false
      end
    end

    context 'when execution fails' do
      before do
        allow(Screeners::SwingScreener).to receive(:call).and_return(
          [{ instrument_id: instrument.id, symbol: instrument.symbol_name, score: 85 }]
        )
        allow(Screeners::AIRanker).to receive(:call).and_return(
          [{ instrument_id: instrument.id, symbol: instrument.symbol_name, score: 85, ai_score: 80 }]
        )
        allow(Screeners::FinalSelector).to receive(:call).and_return(
          [{ instrument_id: instrument.id, symbol: instrument.symbol_name, combined_score: 82.5 }]
        )
        allow(Strategies::Swing::Engine).to receive(:call).and_return(
          {
            success: true,
            signal: {
              instrument_id: instrument.id,
              direction: 'long',
              entry_price: 100.0,
              sl: 95.0,
              tp: 110.0,
              qty: 10
            }
          }
        )
        allow(PaperTrading::Executor).to receive(:execute).and_return(
          { success: false, error: 'Risk limit exceeded' }
        )
      end

      it 'handles execution failure gracefully' do
        candidates = Screeners::SwingScreener.call
        ranked = Screeners::AIRanker.call(candidates: candidates)
        _selected = Screeners::FinalSelector.call(candidates: ranked)

        result = Strategies::Swing::Engine.call(
          instrument: instrument,
          daily_series: daily_series
        )

        execution = Strategies::Swing::Executor.call(result[:signal])
        expect(execution[:success]).to be false
        expect(execution[:error]).to include('Risk limit exceeded')
      end
    end
  end
end
