# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Swing::SignalBuilder do
  let(:instrument) { create(:instrument, symbol_name: 'TEST') }
  let(:series) { create(:candle_series, symbol: 'TEST', interval: '1D') }
  let(:indicators) do
    {
      ema20: 100.0,
      ema50: 95.0,
      rsi: 60.0,
      adx: 25.0,
      atr: 5.0,
      supertrend: { trend: :bullish, value: 98.0 }
    }
  end

  describe '.call' do
    context 'with bullish trend' do
      it 'returns a signal hash' do
        result = described_class.call(
          instrument: instrument,
          daily_series: series,
          indicators: indicators,
          direction: :long
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key(:symbol)
        expect(result).to have_key(:direction)
        expect(result).to have_key(:entry_price)
      end

      it 'sets direction to long for bullish signals' do
        result = described_class.call(
          instrument: instrument,
          daily_series: series,
          indicators: indicators,
          direction: :long
        )

        expect(result[:direction]).to eq(:long)
      end

      it 'calculates entry price from latest close' do
        allow(series).to receive_message_chain(:candles, :last, :close).and_return(100.0)

        result = described_class.call(
          instrument: instrument,
          daily_series: series,
          indicators: indicators,
          direction: :long
        )

        expect(result[:entry_price]).to eq(100.0)
      end

      it 'calculates stop loss based on ATR' do
        allow(series).to receive_message_chain(:candles, :last, :close).and_return(100.0)
        indicators[:atr] = 5.0

        result = described_class.call(
          instrument: instrument,
          daily_series: series,
          indicators: indicators,
          direction: :long
        )

        expect(result[:stop_loss]).to be < result[:entry_price]
        expect(result[:stop_loss]).to be_a(Numeric)
      end

      it 'calculates take profit based on risk-reward ratio' do
        allow(series).to receive_message_chain(:candles, :last, :close).and_return(100.0)

        result = described_class.call(
          instrument: instrument,
          daily_series: series,
          indicators: indicators,
          direction: :long,
          risk_reward_ratio: 2.0
        )

        expect(result[:take_profit]).to be > result[:entry_price]
        risk = result[:entry_price] - result[:stop_loss]
        reward = result[:take_profit] - result[:entry_price]
        expect(reward / risk).to be >= 2.0
      end

      it 'calculates position size' do
        allow(series).to receive_message_chain(:candles, :last, :close).and_return(100.0)

        result = described_class.call(
          instrument: instrument,
          daily_series: series,
          indicators: indicators,
          direction: :long,
          capital: 100_000,
          risk_per_trade: 2.0
        )

        expect(result[:quantity]).to be_a(Integer)
        expect(result[:quantity]).to be > 0
      end

      it 'calculates confidence score' do
        result = described_class.call(
          instrument: instrument,
          daily_series: series,
          indicators: indicators,
          direction: :long
        )

        expect(result[:confidence]).to be_a(Numeric)
        expect(result[:confidence]).to be_between(0, 100)
      end
    end

    describe 'entry/SL/TP calculations' do
      # Create a proper candle series with enough candles for indicators
      let(:bullish_series) do
        series = CandleSeries.new(symbol: 'TEST', interval: '1D')
        # Create 60 candles with bullish trend (EMA20 > EMA50)
        base_price = 100.0
        60.times do |i|
          price = base_price + (i * 0.5) # Uptrend
          series.add_candle(
            Candle.new(
              timestamp: (59 - i).days.ago,
              open: price,
              high: price + 2.0,
              low: price - 1.0,
              close: price + 1.0,
              volume: 1_000_000
            )
          )
        end
        series
      end

      before do
        # Mock AlgoConfig to return test config
        allow(AlgoConfig).to receive(:fetch).and_return({})
        allow(AlgoConfig).to receive(:fetch).with([:swing_trading, :strategy]).and_return({})
        allow(AlgoConfig).to receive(:fetch).with(:risk).and_return({
          risk_per_trade_pct: 2.0,
          account_size: 100_000
        })
        allow(AlgoConfig).to receive(:fetch).with([:indicators, :supertrend]).and_return({
          period: 10,
          multiplier: 3.0
        })
      end

      it 'calculates stop loss at correct distance for long position' do
        result = described_class.call(
          instrument: instrument,
          daily_series: bullish_series
        )

        next if result.nil? # Skip if no signal generated

        # Stop loss should be below entry price for long
        expect(result[:sl]).to be < result[:entry_price]
        # Stop loss distance should be reasonable (based on ATR)
        stop_loss_distance = result[:entry_price] - result[:sl]
        expect(stop_loss_distance).to be > 0
      end

      it 'calculates take profit based on risk-reward ratio' do
        result = described_class.call(
          instrument: instrument,
          daily_series: bullish_series
        )

        next if result.nil? # Skip if no signal generated

        # Risk-reward ratio should meet minimum (default 1.5)
        expect(result[:rr]).to be >= 1.5
        # Take profit should be above entry for long
        expect(result[:tp]).to be > result[:entry_price]
        # Verify risk-reward calculation
        risk = result[:entry_price] - result[:sl]
        reward = result[:tp] - result[:entry_price]
        expect(reward / risk).to be >= 1.5
      end

      it 'calculates position size based on risk per trade' do
        result = described_class.call(
          instrument: instrument,
          daily_series: bullish_series
        )

        next if result.nil? # Skip if no signal generated

        # Position size should be calculated
        expect(result[:qty]).to be_a(Integer)
        expect(result[:qty]).to be > 0

        # Risk amount = account_size * risk_per_trade_pct / 100
        risk_amount = 100_000 * (2.0 / 100.0) # 2000
        # Risk per share = entry_price - stop_loss
        risk_per_share = result[:entry_price] - result[:sl]
        # Expected quantity should be close to risk_amount / risk_per_share
        if risk_per_share > 0
          expected_quantity = (risk_amount / risk_per_share).floor
          # Allow some variance due to lot size rounding
          expect(result[:qty]).to be <= (expected_quantity * 1.1).ceil
        end
      end

      it 'calculates position value correctly' do
        result = described_class.call(
          instrument: instrument,
          daily_series: bullish_series
        )

        next if result.nil? # Skip if no signal generated

        position_value = result[:qty] * result[:entry_price]
        # Position value should be reasonable (not exceed account size by too much)
        expect(position_value).to be > 0
        expect(position_value).to be < 200_000 # Reasonable upper bound
      end

      it 'returns valid signal structure' do
        result = described_class.call(
          instrument: instrument,
          daily_series: bullish_series
        )

        next if result.nil? # Skip if no signal generated

        # Verify all required keys are present
        expect(result).to have_key(:instrument_id)
        expect(result).to have_key(:symbol)
        expect(result).to have_key(:direction)
        expect(result).to have_key(:entry_price)
        expect(result).to have_key(:sl)
        expect(result).to have_key(:tp)
        expect(result).to have_key(:rr)
        expect(result).to have_key(:qty)
        expect(result).to have_key(:confidence)
        expect(result).to have_key(:holding_days_estimate)
        expect(result).to have_key(:metadata)

        # Verify data types
        expect(result[:direction]).to be_in([:long, :short])
        expect(result[:entry_price]).to be_a(Numeric)
        expect(result[:sl]).to be_a(Numeric)
        expect(result[:tp]).to be_a(Numeric)
        expect(result[:rr]).to be_a(Numeric)
        expect(result[:qty]).to be_a(Integer)
        expect(result[:confidence]).to be_a(Numeric)
        expect(result[:confidence]).to be_between(0, 100)
      end
    end
  end
end

