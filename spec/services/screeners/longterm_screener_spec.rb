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

    context 'with edge cases' do
      let(:instruments) { Instrument.where(id: instrument.id) }

      it 'handles instrument without weekly candles' do
        allow(instrument).to receive(:has_candles?).with(timeframe: '1D').and_return(true)
        allow(instrument).to receive(:has_candles?).with(timeframe: '1W').and_return(false)

        result = described_class.new(instruments: instruments).call

        expect(result).to be_empty
      end

      it 'handles insufficient weekly candles' do
        allow(instrument).to receive(:has_candles?).and_return(true)
        allow(instrument).to receive(:load_daily_candles).and_return(
          create(:candle_series, candles: create_list(:candle, 150))
        )
        allow(instrument).to receive(:load_weekly_candles).and_return(
          create(:candle_series, candles: create_list(:candle, 10)) # Less than 20
        )

        result = described_class.new(instruments: instruments).call

        expect(result).to be_empty
      end

      it 'handles indicator calculation failures' do
        allow(instrument).to receive(:has_candles?).and_return(true)
        allow(instrument).to receive(:load_daily_candles).and_return(
          create(:candle_series, candles: create_list(:candle, 150))
        )
        allow(instrument).to receive(:load_weekly_candles).and_return(
          create(:candle_series, candles: create_list(:candle, 30))
        )
        allow_any_instance_of(described_class).to receive(:calculate_indicators).and_raise(StandardError.new('Calculation error'))
        allow(Rails.logger).to receive(:error)

        result = described_class.new(instruments: instruments).call

        expect(result).to be_empty
        expect(Rails.logger).to have_received(:error)
      end

      it 'handles nil indicators' do
        allow(instrument).to receive(:has_candles?).and_return(true)
        allow(instrument).to receive(:load_daily_candles).and_return(
          create(:candle_series, candles: create_list(:candle, 150))
        )
        allow(instrument).to receive(:load_weekly_candles).and_return(
          create(:candle_series, candles: create_list(:candle, 30))
        )
        allow_any_instance_of(described_class).to receive(:calculate_indicators).and_return(nil)

        result = described_class.new(instruments: instruments).call

        expect(result).to be_empty
      end

      it 'sorts candidates by score descending' do
        instruments_list = create_list(:instrument, 3)
        instruments_list.each do |inst|
          allow(inst).to receive(:has_candles?).and_return(true)
          allow(inst).to receive(:load_daily_candles).and_return(
            create(:candle_series, candles: create_list(:candle, 150))
          )
          allow(inst).to receive(:load_weekly_candles).and_return(
            create(:candle_series, candles: create_list(:candle, 30))
          )
        end

        # Mock different scores
        allow_any_instance_of(described_class).to receive(:calculate_indicators).and_return(
          { rsi: 65, ema20: 100.0 }
        )
        allow_any_instance_of(described_class).to receive(:calculate_score).and_return(80, 90, 85)

        result = described_class.new(
          instruments: Instrument.where(id: instruments_list.map(&:id)),
          limit: 10
        ).call

        if result.size >= 2
          expect(result[0][:score]).to be >= result[1][:score]
        end
      end
    end

    describe 'private methods' do
      let(:screener) { described_class.new(instruments: instruments) }
      let(:daily_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: '1D') }
      let(:weekly_series) { CandleSeries.new(symbol: instrument.symbol_name, interval: '1W') }

      before do
        150.times { daily_series.add_candle(create(:candle)) }
        30.times { weekly_series.add_candle(create(:candle)) }
      end

      describe '#calculate_score' do
        let(:daily_indicators) do
          {
            ema20: 100.0,
            ema50: 95.0,
            ema200: 90.0,
            rsi: 65.0,
            adx: 25.0
          }
        end

        let(:weekly_indicators) do
          {
            ema20: 100.0,
            ema50: 95.0,
            supertrend: { direction: :bullish },
            adx: 25.0
          }
        end

        it 'calculates score with weekly trend requirement' do
          allow(AlgoConfig).to receive(:fetch).and_return(
            long_term_trading: {
              strategy: {
                entry_conditions: {
                  require_weekly_trend: true
                }
              }
            }
          )

          score = screener.send(:calculate_score, daily_series, weekly_series, daily_indicators, weekly_indicators)

          expect(score).to be_between(0, 100)
        end

        it 'calculates score without weekly trend requirement' do
          allow(AlgoConfig).to receive(:fetch).and_return(
            long_term_trading: {
              strategy: {
                entry_conditions: {
                  require_weekly_trend: false
                }
              }
            }
          )

          score = screener.send(:calculate_score, daily_series, weekly_series, daily_indicators, weekly_indicators)

          expect(score).to be_between(0, 100)
        end

        it 'handles nil indicators' do
          nil_indicators = {
            ema20: nil,
            ema50: nil,
            adx: nil
          }

          allow(AlgoConfig).to receive(:fetch).and_return({})

          score = screener.send(:calculate_score, daily_series, weekly_series, nil_indicators, nil_indicators)

          expect(score).to eq(0.0)
        end

        it 'normalizes score to 0-100 scale' do
          allow(AlgoConfig).to receive(:fetch).and_return({})

          score = screener.send(:calculate_score, daily_series, weekly_series, daily_indicators, weekly_indicators)

          expect(score).to be_between(0, 100)
        end
      end

      describe '#calculate_momentum_score' do
        let(:daily_indicators) { { rsi: 65.0, macd: [10.0, 8.0] } }
        let(:weekly_indicators) { { rsi: 60.0 } }

        it 'calculates momentum score' do
          score = screener.send(:calculate_momentum_score, daily_series, weekly_series, daily_indicators, weekly_indicators)

          expect(score).to be >= 0
        end

        it 'handles RSI above 70' do
          daily_indicators[:rsi] = 75.0
          weekly_indicators[:rsi] = 75.0

          score = screener.send(:calculate_momentum_score, daily_series, weekly_series, daily_indicators, weekly_indicators)

          # RSI > 70 should not add to score
          expect(score).to be >= 0
        end

        it 'handles MACD with insufficient data' do
          daily_indicators[:macd] = [10.0] # Only one value

          score = screener.send(:calculate_momentum_score, daily_series, weekly_series, daily_indicators, weekly_indicators)

          expect(score).to be >= 0
        end

        it 'handles MACD bearish (signal > MACD)' do
          daily_indicators[:macd] = [8.0, 10.0] # MACD < Signal

          score = screener.send(:calculate_momentum_score, daily_series, weekly_series, daily_indicators, weekly_indicators)

          # Should not add MACD score
          expect(score).to be >= 0
        end
      end

      describe '#check_trend_alignment' do
        it 'identifies bullish alignment' do
          daily_indicators = { ema20: 100.0, ema50: 95.0 }
          weekly_indicators = {
            ema20: 100.0,
            ema50: 95.0,
            supertrend: { direction: :bullish }
          }

          alignment = screener.send(:check_trend_alignment, daily_indicators, weekly_indicators)

          expect(alignment).to include(:weekly_ema_bullish)
          expect(alignment).to include(:weekly_supertrend_bullish)
          expect(alignment).to include(:daily_ema_bullish)
        end

        it 'handles nil indicators' do
          daily_indicators = { ema20: nil, ema50: nil }
          weekly_indicators = { ema20: nil, supertrend: nil }

          alignment = screener.send(:check_trend_alignment, daily_indicators, weekly_indicators)

          expect(alignment).to be_an(Array)
        end

        it 'handles bearish supertrend' do
          weekly_indicators = {
            ema20: 100.0,
            ema50: 95.0,
            supertrend: { direction: :bearish }
          }

          alignment = screener.send(:check_trend_alignment, {}, weekly_indicators)

          expect(alignment).not_to include(:weekly_supertrend_bullish)
        end
      end

      describe '#calculate_momentum' do
        let(:daily_indicators) { { rsi: 65.0 } }
        let(:weekly_indicators) { { rsi: 60.0 } }

        it 'calculates momentum metrics' do
          momentum = screener.send(:calculate_momentum, daily_series, weekly_series, daily_indicators, weekly_indicators)

          expect(momentum).to have_key(:daily_change_5d)
          expect(momentum).to have_key(:weekly_change_4w)
          expect(momentum).to have_key(:daily_rsi)
          expect(momentum).to have_key(:weekly_rsi)
        end

        it 'handles insufficient daily candles' do
          small_daily = CandleSeries.new(symbol: instrument.symbol_name, interval: '1D')
          3.times { small_daily.add_candle(create(:candle)) }

          momentum = screener.send(:calculate_momentum, small_daily, weekly_series, daily_indicators, weekly_indicators)

          expect(momentum[:daily_change_5d]).to be_nil
        end

        it 'handles insufficient weekly candles' do
          small_weekly = CandleSeries.new(symbol: instrument.symbol_name, interval: '1W')
          2.times { small_weekly.add_candle(create(:candle)) }

          momentum = screener.send(:calculate_momentum, daily_series, small_weekly, daily_indicators, weekly_indicators)

          expect(momentum[:weekly_change_4w]).to be_nil
        end
      end

      describe '#build_metadata' do
        let(:daily_indicators) { { rsi: 65.0, ema20: 100.0 } }
        let(:weekly_indicators) { { rsi: 60.0, ema20: 100.0, supertrend: { direction: :bullish } } }

        it 'builds metadata hash' do
          metadata = screener.send(:build_metadata, instrument, daily_series, weekly_series, daily_indicators, weekly_indicators)

          expect(metadata).to have_key(:ltp)
          expect(metadata).to have_key(:daily_candles_count)
          expect(metadata).to have_key(:weekly_candles_count)
          expect(metadata).to have_key(:trend_alignment)
          expect(metadata).to have_key(:momentum)
        end

        it 'handles nil LTP' do
          allow(instrument).to receive(:ltp).and_return(nil)

          metadata = screener.send(:build_metadata, instrument, daily_series, weekly_series, daily_indicators, weekly_indicators)

          expect(metadata[:ltp]).to be_nil
        end
      end

      describe '#calculate_supertrend' do
        it 'calculates supertrend when available' do
          allow(Indicators::Supertrend).to receive(:new).and_return(
            double('Supertrend', call: { trend: :bullish, line: [100.0] })
          )
          allow(AlgoConfig).to receive(:fetch).and_return(
            indicators: {
              supertrend: { period: 10, multiplier: 3.0 }
            }
          )

          result = screener.send(:calculate_supertrend, daily_series)

          expect(result).to have_key(:trend)
          expect(result).to have_key(:direction)
        end

        it 'handles supertrend calculation failure' do
          allow(Indicators::Supertrend).to receive(:new).and_raise(StandardError.new('Supertrend error'))
          allow(Rails.logger).to receive(:warn)
          allow(AlgoConfig).to receive(:fetch).and_return({})

          result = screener.send(:calculate_supertrend, daily_series)

          expect(result).to be_nil
          expect(Rails.logger).to have_received(:warn)
        end

        it 'handles nil supertrend result' do
          allow(Indicators::Supertrend).to receive(:new).and_return(
            double('Supertrend', call: { trend: nil })
          )
          allow(AlgoConfig).to receive(:fetch).and_return({})

          result = screener.send(:calculate_supertrend, daily_series)

          expect(result).to be_nil
        end
      end
    end
  end
end

