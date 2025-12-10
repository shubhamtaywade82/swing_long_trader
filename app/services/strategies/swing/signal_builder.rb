# frozen_string_literal: true

module Strategies
  module Swing
    class SignalBuilder < ApplicationService
      DEFAULT_RISK_PCT = 2.0 # 2% risk per trade
      DEFAULT_MIN_RR = 1.5 # Minimum risk-reward ratio

      def self.call(instrument:, daily_series:, weekly_series: nil, config: {})
        new(instrument: instrument, daily_series: daily_series, weekly_series: weekly_series, config: config).call
      end

      def initialize(instrument:, daily_series:, weekly_series: nil, config: {})
        @instrument = instrument
        @daily_series = daily_series
        @weekly_series = weekly_series
        @config = config || AlgoConfig.fetch([:swing_trading, :strategy]) || {}
        @exit_config = @config[:exit_conditions] || {}
        @risk_config = AlgoConfig.fetch(:risk) || {}
      end

      def call
        return nil unless validate_inputs

        # Determine direction
        direction = determine_direction
        return nil unless direction

        # Calculate entry price
        entry_price = calculate_entry_price(direction)
        return nil unless entry_price

        # Calculate stop loss
        stop_loss = calculate_stop_loss(entry_price, direction)
        return nil unless stop_loss

        # Calculate take profit
        take_profit = calculate_take_profit(entry_price, stop_loss, direction)
        return nil unless take_profit

        # Calculate risk-reward ratio
        risk_reward = calculate_risk_reward(entry_price, stop_loss, take_profit, direction)

        # Validate minimum risk-reward
        return nil if risk_reward < (DEFAULT_MIN_RR || @config[:min_risk_reward] || 1.5)

        # Calculate position size
        quantity = calculate_position_size(entry_price, stop_loss)

        # Calculate confidence
        confidence = calculate_confidence(direction)

        # Estimate holding days
        holding_days = estimate_holding_days

        {
          instrument_id: @instrument.id,
          symbol: @instrument.symbol_name,
          direction: direction,
          entry_price: entry_price.round(2),
          sl: stop_loss.round(2),
          tp: take_profit.round(2),
          rr: risk_reward.round(2),
          qty: quantity,
          confidence: confidence.round(2),
          holding_days_estimate: holding_days,
          metadata: build_metadata(entry_price, stop_loss, take_profit, direction)
        }
      end

      private

      def validate_inputs
        return false unless @instrument.present?
        return false unless @daily_series&.candles&.any?
        return false if @daily_series.candles.size < 50

        true
      end

      def determine_direction
        # Use Supertrend and EMA alignment to determine direction
        indicators = calculate_indicators

        # Check Supertrend
        if indicators[:supertrend] && indicators[:supertrend][:direction] == :bullish
          return :long if indicators[:ema20] && indicators[:ema50] && indicators[:ema20] > indicators[:ema50]
        end

        # Check for bearish setup (optional for short trading)
        if indicators[:supertrend] && indicators[:supertrend][:direction] == :bearish
          return :short if indicators[:ema20] && indicators[:ema50] && indicators[:ema20] < indicators[:ema50]
        end

        nil
      end

      def calculate_indicators
        {
          ema20: @daily_series.ema(20),
          ema50: @daily_series.ema(50),
          ema200: @daily_series.ema(200),
          atr: @daily_series.atr(14),
          supertrend: calculate_supertrend,
          latest_close: @daily_series.candles.last&.close
        }
      end

      def calculate_supertrend
        st_config = AlgoConfig.fetch([:indicators, :supertrend]) || {}
        period = st_config[:period] || 10
        multiplier = st_config[:multiplier] || 3.0

        supertrend = Indicators::Supertrend.new(
          series: @daily_series,
          period: period,
          base_multiplier: multiplier
        )
        result = supertrend.call

        return nil unless result && result[:trend]

        {
          trend: result[:trend],
          value: result[:line]&.last,
          direction: result[:trend] == :bullish ? :bullish : :bearish
        }
      rescue StandardError => e
        Rails.logger.warn("[Strategies::Swing::SignalBuilder] Supertrend failed: #{e.message}")
        nil
      end

      def calculate_entry_price(direction)
        latest_candle = @daily_series.candles.last
        return nil unless latest_candle

        latest_close = latest_candle.close
        atr = @daily_series.atr(14) || (latest_close * 0.02) # Fallback to 2% if ATR unavailable

        case direction
        when :long
          # Entry on breakout above recent high or retest of support
          recent_high = @daily_series.candles.last(20).map(&:high).max
          entry = [recent_high, latest_close].max
          # Add small buffer for breakout entry
          entry + (atr * 0.1)
        when :short
          # Entry on breakdown below recent low or retest of resistance
          recent_low = @daily_series.candles.last(20).map(&:low).min
          entry = [recent_low, latest_close].min
          # Subtract small buffer for breakdown entry
          entry - (atr * 0.1)
        else
          latest_close
        end
      end

      def calculate_stop_loss(entry_price, direction)
        atr = @daily_series.atr(14) || (entry_price * 0.02)
        stop_loss_pct = @exit_config[:stop_loss_pct] || 8.0

        case direction
        when :long
          # Stop loss below recent swing low or ATR-based
          recent_low = @daily_series.candles.last(20).map(&:low).min
          atr_based_sl = entry_price - (atr * 2.0)
          pct_based_sl = entry_price * (1 - stop_loss_pct / 100.0)
          [recent_low, atr_based_sl, pct_based_sl].min
        when :short
          # Stop loss above recent swing high or ATR-based
          recent_high = @daily_series.candles.last(20).map(&:high).max
          atr_based_sl = entry_price + (atr * 2.0)
          pct_based_sl = entry_price * (1 + stop_loss_pct / 100.0)
          [recent_high, atr_based_sl, pct_based_sl].max
        else
          nil
        end
      end

      def calculate_take_profit(entry_price, stop_loss, direction)
        profit_target_pct = @exit_config[:profit_target_pct] || 15.0
        atr = @daily_series.atr(14) || (entry_price * 0.02)

        case direction
        when :long
          # Take profit: risk-reward based or ATR-based
          risk = entry_price - stop_loss
          rr_target = risk * (DEFAULT_MIN_RR * 1.5) # Target 2.25x RR
          pct_target = entry_price * (1 + profit_target_pct / 100.0)
          atr_target = entry_price + (atr * 3.0)
          [rr_target + entry_price, pct_target, atr_target].min
        when :short
          # Take profit: risk-reward based or ATR-based
          risk = stop_loss - entry_price
          rr_target = risk * (DEFAULT_MIN_RR * 1.5)
          pct_target = entry_price * (1 - profit_target_pct / 100.0)
          atr_target = entry_price - (atr * 3.0)
          [entry_price - rr_target, pct_target, atr_target].max
        else
          nil
        end
      end

      def calculate_risk_reward(entry_price, stop_loss, take_profit, direction)
        case direction
        when :long
          risk = entry_price - stop_loss
          reward = take_profit - entry_price
        when :short
          risk = stop_loss - entry_price
          reward = entry_price - take_profit
        else
          return 0
        end

        return 0 if risk <= 0

        (reward / risk).round(2)
      end

      def calculate_position_size(entry_price, stop_loss)
        # Risk-based position sizing
        risk_pct = @risk_config[:risk_per_trade_pct] || DEFAULT_RISK_PCT
        account_size = @risk_config[:account_size] || 100_000 # Default 1 lakh

        case @daily_series.candles.last&.close && @instrument.ltp
        when :long
          risk_amount = account_size * (risk_pct / 100.0)
          risk_per_share = entry_price - stop_loss
        when :short
          risk_amount = account_size * (risk_pct / 100.0)
          risk_per_share = stop_loss - entry_price
        else
          return 0
        end

        return 0 if risk_per_share <= 0

        quantity = (risk_amount / risk_per_share).floor

        # Apply lot size if available
        if @instrument.lot_size && @instrument.lot_size > 1
          quantity = (quantity / @instrument.lot_size) * @instrument.lot_size
        end

        [quantity, 1].max # Minimum 1 share
      end

      def calculate_confidence(direction)
        indicators = calculate_indicators
        confidence = 0.0

        # Trend alignment (30 points)
        if indicators[:ema20] && indicators[:ema50] && indicators[:ema20] > indicators[:ema50]
          confidence += 15
        end
        if indicators[:ema20] && indicators[:ema200] && indicators[:ema20] > indicators[:ema200]
          confidence += 15
        end

        # Supertrend alignment (20 points)
        if indicators[:supertrend] && indicators[:supertrend][:direction] == :bullish
          confidence += 20
        end

        # ADX strength (20 points)
        adx = @daily_series.adx(14)
        if adx
          if adx > 25
            confidence += 20
          elsif adx > 20
            confidence += 10
          end
        end

        # RSI condition (15 points)
        rsi = @daily_series.rsi(14)
        if rsi
          if rsi > 50 && rsi < 70
            confidence += 15
          elsif rsi > 40 && rsi < 60
            confidence += 8
          end
        end

        # MACD bullish (15 points)
        macd_result = @daily_series.macd(12, 26, 9)
        if macd_result && macd_result.is_a?(Array) && macd_result.size >= 2
          macd_line, signal_line = macd_result[0], macd_result[1]
          if macd_line && signal_line && macd_line > signal_line
            confidence += 15
          end
        end

        # Normalize to 0-100
        [confidence, 100].min.round(2)
      end

      def estimate_holding_days
        # Estimate based on profit target and volatility
        profit_target_pct = @exit_config[:profit_target_pct] || 15.0
        atr_pct = if @daily_series.atr(14) && @daily_series.candles.last&.close
                    (@daily_series.atr(14) / @daily_series.candles.last.close * 100).round(2)
                  else
                    2.0
                  end

        # Rough estimate: days needed to reach profit target at current volatility
        days = (profit_target_pct / (atr_pct * 1.5)).ceil

        # Clamp to reasonable range for swing trading
        [[days, 5].max, 20].min
      end

      def build_metadata(entry_price, stop_loss, take_profit, direction)
        indicators = calculate_indicators
        {
          atr: indicators[:atr],
          atr_pct: indicators[:atr] && indicators[:latest_close] ? (indicators[:atr] / indicators[:latest_close] * 100).round(2) : nil,
          ema20: indicators[:ema20],
          ema50: indicators[:ema50],
          ema200: indicators[:ema200],
          supertrend_direction: indicators[:supertrend]&.dig(:direction),
          risk_amount: calculate_risk_amount(entry_price, stop_loss),
          created_at: Time.current
        }
      end

      def calculate_risk_amount(entry_price, stop_loss)
        quantity = calculate_position_size(entry_price, stop_loss)
        risk_per_share = (entry_price - stop_loss).abs
        (quantity * risk_per_share).round(2)
      end
    end
  end
end

