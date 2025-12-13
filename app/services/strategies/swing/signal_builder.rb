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
        @config = config || AlgoConfig.fetch(%i[swing_trading strategy]) || {}
        @exit_config = @config[:exit_conditions] || {}
        @risk_config = AlgoConfig.fetch(:risk) || {}
        @mtf_config = @config[:multi_timeframe] || {}
      end

      def call
        return nil unless validate_inputs

        # Multi-timeframe analysis
        mtf_result = Swing::MultiTimeframeAnalyzer.call(
          instrument: @instrument,
          include_intraday: @mtf_config[:include_intraday] != false,
        )

        mtf_analysis = mtf_result[:success] ? mtf_result[:analysis] : nil

        # Determine direction (enhanced with MTF)
        direction = determine_direction(mtf_analysis)
        return nil unless direction

        # Use MTF entry recommendations if available
        entry_price = if mtf_analysis && mtf_analysis[:entry_recommendations].any?
                       calculate_entry_from_mtf(mtf_analysis, direction)
                     else
                       calculate_entry_price(direction)
                     end
        return nil unless entry_price

        # Calculate stop loss (enhanced with MTF support/resistance)
        stop_loss = calculate_stop_loss(entry_price, direction, mtf_analysis)
        return nil unless stop_loss

        # Calculate take profit
        take_profit = calculate_take_profit(entry_price, stop_loss, direction, mtf_analysis)
        return nil unless take_profit

        # Calculate risk-reward ratio
        risk_reward = calculate_risk_reward(entry_price, stop_loss, take_profit, direction)

        # Validate minimum risk-reward
        return nil if risk_reward < (DEFAULT_MIN_RR || @config[:min_risk_reward] || 1.5)

        # Calculate position size
        quantity = calculate_position_size(entry_price, stop_loss)

        # Calculate confidence (enhanced with MTF)
        confidence = calculate_confidence(direction, mtf_analysis)

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
          metadata: build_metadata(entry_price, stop_loss, take_profit, direction, mtf_analysis),
        }
      end

      private

      def validate_inputs
        return false if @instrument.blank?
        return false unless @daily_series&.candles&.any?
        return false if @daily_series.candles.size < 50

        true
      end

      def determine_direction(mtf_analysis = nil)
        # Use multi-timeframe trend alignment if available
        if mtf_analysis && mtf_analysis[:trend_alignment][:aligned]
          return :long if mtf_analysis[:trend_alignment][:bullish_count] > mtf_analysis[:trend_alignment][:bearish_count]
        end

        # Fallback to daily timeframe analysis
        indicators = calculate_indicators

        # Check Supertrend
        if indicators[:supertrend] && indicators[:supertrend][:direction] == :bullish && indicators[:ema20] && indicators[:ema50] && indicators[:ema20] > indicators[:ema50]
          return :long
        end

        # Check for bearish setup (optional for short trading)
        if indicators[:supertrend] && indicators[:supertrend][:direction] == :bearish && indicators[:ema20] && indicators[:ema50] && indicators[:ema20] < indicators[:ema50]
          return :short
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
          latest_close: @daily_series.candles.last&.close,
        }
      end

      def calculate_supertrend
        st_config = AlgoConfig.fetch(%i[indicators supertrend]) || {}
        period = st_config[:period] || 10
        multiplier = st_config[:multiplier] || 3.0

        supertrend = Indicators::Supertrend.new(
          series: @daily_series,
          period: period,
          base_multiplier: multiplier,
        )
        result = supertrend.call

        return nil unless result && result[:trend]

        {
          trend: result[:trend],
          value: result[:line]&.last,
          direction: result[:trend] == :bullish ? :bullish : :bearish,
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

      def calculate_stop_loss(entry_price, direction, mtf_analysis = nil)
        atr = @daily_series.atr(14) || (entry_price * 0.02)
        stop_loss_pct = @exit_config[:stop_loss_pct] || 8.0

        case direction
        when :long
          # Use MTF support levels if available
          if mtf_analysis && mtf_analysis[:support_resistance][:support_levels].any?
            nearest_support = mtf_analysis[:support_resistance][:support_levels].first
            support_based_sl = nearest_support * 0.98 # 2% below support
          end

          recent_low = @daily_series.candles.last(20).map(&:low).min
          atr_based_sl = entry_price - (atr * 2.0)
          pct_based_sl = entry_price * (1 - (stop_loss_pct / 100.0))

          candidates = [recent_low, atr_based_sl, pct_based_sl]
          candidates << support_based_sl if support_based_sl
          candidates.min
        when :short
          # Use MTF resistance levels if available
          if mtf_analysis && mtf_analysis[:support_resistance][:resistance_levels].any?
            nearest_resistance = mtf_analysis[:support_resistance][:resistance_levels].first
            resistance_based_sl = nearest_resistance * 1.02 # 2% above resistance
          end

          recent_high = @daily_series.candles.last(20).map(&:high).max
          atr_based_sl = entry_price + (atr * 2.0)
          pct_based_sl = entry_price * (1 + (stop_loss_pct / 100.0))

          candidates = [recent_high, atr_based_sl, pct_based_sl]
          candidates << resistance_based_sl if resistance_based_sl
          candidates.max
        end
      end

      def calculate_entry_from_mtf(mtf_analysis, direction)
        recommendations = mtf_analysis[:entry_recommendations]
        return nil if recommendations.empty?

        # Prefer recommendations with intraday confirmation
        best_rec = recommendations.find { |r| r[:intraday_confirmation]&.dig(:m15_bullish) } ||
                   recommendations.find { |r| r[:intraday_confirmation]&.dig(:h1_bullish) } ||
                   recommendations.first

        entry_zone = best_rec[:entry_zone]

        # For intraday pullback entries, use the lower bound (support level)
        if best_rec[:type] == :intraday_pullback
          entry_zone[0]
        else
          # Use middle of entry zone for other types
          (entry_zone[0] + entry_zone[1]) / 2.0
        end
      end

      def calculate_take_profit(entry_price, stop_loss, direction, mtf_analysis = nil)
        profit_target_pct = @exit_config[:profit_target_pct] || 15.0
        atr = @daily_series.atr(14) || (entry_price * 0.02)

        case direction
        when :long
          # Use MTF resistance levels if available
          if mtf_analysis && mtf_analysis[:support_resistance][:resistance_levels].any?
            nearest_resistance = mtf_analysis[:support_resistance][:resistance_levels].first
            resistance_target = nearest_resistance * 0.99 # Slightly below resistance
          end

          risk = entry_price - stop_loss
          rr_target = risk * (DEFAULT_MIN_RR * 1.5) # Target 2.25x RR
          pct_target = entry_price * (1 + (profit_target_pct / 100.0))
          atr_target = entry_price + (atr * 3.0)

          candidates = [rr_target + entry_price, pct_target, atr_target]
          candidates << resistance_target if resistance_target
          candidates.min
        when :short
          # Use MTF support levels if available
          if mtf_analysis && mtf_analysis[:support_resistance][:support_levels].any?
            nearest_support = mtf_analysis[:support_resistance][:support_levels].first
            support_target = nearest_support * 1.01 # Slightly above support
          end

          risk = stop_loss - entry_price
          rr_target = risk * (DEFAULT_MIN_RR * 1.5)
          pct_target = entry_price * (1 - (profit_target_pct / 100.0))
          atr_target = entry_price - (atr * 3.0)

          candidates = [entry_price - rr_target, pct_target, atr_target]
          candidates << support_target if support_target
          candidates.max
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

      def calculate_confidence(_direction, mtf_analysis = nil)
        indicators = calculate_indicators
        confidence = 0.0

        # Base confidence from daily timeframe (60 points)
        confidence += 15 if indicators[:ema20] && indicators[:ema50] && indicators[:ema20] > indicators[:ema50]
        confidence += 15 if indicators[:ema20] && indicators[:ema200] && indicators[:ema20] > indicators[:ema200]
        confidence += 20 if indicators[:supertrend] && indicators[:supertrend][:direction] == :bullish

        adx = @daily_series.adx(14)
        if adx
          confidence += 20 if adx > 25
          confidence += 10 if adx > 20 && adx <= 25
        end

        # Multi-timeframe boost (40 points)
        if mtf_analysis
          # Trend alignment boost
          if mtf_analysis[:trend_alignment][:aligned]
            alignment_score = (mtf_analysis[:trend_alignment][:bullish_count].to_f / mtf_analysis[:timeframes].size * 100).round(2)
            confidence += (alignment_score * 0.2).round(2) # Up to 20 points
          end

          # Momentum alignment boost
          if mtf_analysis[:momentum_alignment][:aligned]
            confidence += 10
          end

          # MTF score boost
          mtf_score = mtf_analysis[:multi_timeframe_score] || 0
          confidence += (mtf_score * 0.1).round(2) # Up to 10 points
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

      def build_metadata(entry_price, stop_loss, _take_profit, _direction, mtf_analysis = nil)
        indicators = calculate_indicators
        metadata = {
          atr: indicators[:atr],
          atr_pct: indicators[:atr] && indicators[:latest_close] ? (indicators[:atr] / indicators[:latest_close] * 100).round(2) : nil,
          ema20: indicators[:ema20],
          ema50: indicators[:ema50],
          ema200: indicators[:ema200],
          supertrend_direction: indicators[:supertrend]&.dig(:direction),
          risk_amount: calculate_risk_amount(entry_price, stop_loss),
          created_at: Time.current,
        }

        # Add multi-timeframe metadata
        if mtf_analysis
          metadata[:multi_timeframe] = {
            score: mtf_analysis[:multi_timeframe_score],
            trend_alignment: mtf_analysis[:trend_alignment],
            momentum_alignment: mtf_analysis[:momentum_alignment],
            timeframes_analyzed: mtf_analysis[:timeframes].keys.map(&:to_s),
            support_levels: mtf_analysis[:support_resistance][:support_levels],
            resistance_levels: mtf_analysis[:support_resistance][:resistance_levels],
          }
        end

        metadata
      end

      def calculate_risk_amount(entry_price, stop_loss)
        quantity = calculate_position_size(entry_price, stop_loss)
        risk_per_share = (entry_price - stop_loss).abs
        (quantity * risk_per_share).round(2)
      end
    end
  end
end
