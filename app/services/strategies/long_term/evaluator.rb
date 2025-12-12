# frozen_string_literal: true

module Strategies
  module LongTerm
    class Evaluator < ApplicationService
      def self.call(candidate)
        new(candidate: candidate).call
      end

      def initialize(candidate:)
        @candidate = candidate
        @instrument = Instrument.find_by(id: candidate[:instrument_id])
        @config = AlgoConfig.fetch(%i[long_term_trading strategy]) || {}
      end

      def call
        return { success: false, error: "Invalid candidate" } if @candidate.blank?
        return { success: false, error: "Instrument not found" } if @instrument.blank?

        # Load candles
        daily_series = @instrument.load_daily_candles(limit: 200)
        weekly_series = @instrument.load_weekly_candles(limit: 52)

        return { success: false, error: "Failed to load candles" } unless daily_series&.candles&.any?
        return { success: false, error: "Failed to load weekly candles" } unless weekly_series&.candles&.any?

        # Check entry conditions
        entry_check = check_entry_conditions(daily_series, weekly_series)
        return { success: false, error: entry_check[:error] } unless entry_check[:allowed]

        # Build signal for long-term
        signal = build_long_term_signal(daily_series, weekly_series)

        return { success: false, error: "Signal generation failed" } unless signal

        {
          success: true,
          signal: signal,
          metadata: {
            evaluated_at: Time.current,
            daily_candles: daily_series.candles.size,
            weekly_candles: weekly_series.candles.size,
          },
        }
      end

      private

      def check_entry_conditions(daily_series, weekly_series)
        entry_config = @config[:entry_conditions] || {}

        # Check weekly trend requirement
        if entry_config[:require_weekly_trend]
          weekly_indicators = calculate_indicators(weekly_series)
          unless weekly_indicators[:ema20] && weekly_indicators[:ema50]
            return { allowed: false,
                     error: "Weekly trend not bullish" }
          end
          unless weekly_indicators[:ema20] > weekly_indicators[:ema50]
            return { allowed: false,
                     error: "Weekly EMA not aligned" }
          end
        end

        # Check momentum score
        if entry_config[:min_momentum_score]
          momentum = calculate_momentum_score(daily_series, weekly_series)
          if momentum < entry_config[:min_momentum_score]
            return { allowed: false,
                     error: "Momentum too low: #{momentum}" }
          end
        end

        { allowed: true }
      end

      def calculate_indicators(series)
        {
          ema20: series.ema(20),
          ema50: series.ema(50),
          ema200: series.ema(200),
          rsi: series.rsi(14),
          adx: series.adx(14),
        }
      end

      def calculate_momentum_score(daily_series, weekly_series)
        daily_indicators = calculate_indicators(daily_series)
        weekly_indicators = calculate_indicators(weekly_series)

        score = 0.0

        # RSI momentum
        score += 0.2 if daily_indicators[:rsi] && daily_indicators[:rsi] > 50
        score += 0.2 if weekly_indicators[:rsi] && weekly_indicators[:rsi] > 50

        # ADX strength
        score += 0.3 if daily_indicators[:adx] && daily_indicators[:adx] > 20
        score += 0.3 if weekly_indicators[:adx] && weekly_indicators[:adx] > 20

        score
      end

      def build_long_term_signal(daily_series, _weekly_series)
        latest_close = daily_series.candles.last&.close
        return nil unless latest_close

        exit_config = @config[:exit_conditions] || {}
        profit_target_pct = exit_config[:profit_target_pct] || 30.0
        stop_loss_pct = exit_config[:stop_loss_pct] || 15.0

        entry_price = latest_close
        stop_loss = entry_price * (1 - (stop_loss_pct / 100.0))
        take_profit = entry_price * (1 + (profit_target_pct / 100.0))

        risk_reward = ((take_profit - entry_price) / (entry_price - stop_loss)).round(2)

        {
          instrument_id: @instrument.id,
          symbol: @instrument.symbol_name,
          direction: :long,
          entry_price: entry_price.round(2),
          sl: stop_loss.round(2),
          tp: take_profit.round(2),
          rr: risk_reward,
          qty: calculate_position_size(entry_price, stop_loss),
          confidence: 70.0, # Default for long-term
          holding_days_estimate: @config[:holding_period_days] || 30,
          metadata: {
            strategy_type: :long_term,
            created_at: Time.current,
          },
        }
      end

      def calculate_position_size(entry_price, stop_loss)
        risk_config = AlgoConfig.fetch(:risk) || {}
        risk_pct = risk_config[:risk_per_trade_pct] || 2.0
        account_size = risk_config[:account_size] || 100_000

        risk_amount = account_size * (risk_pct / 100.0)
        risk_per_share = entry_price - stop_loss

        return 0 if risk_per_share <= 0

        quantity = (risk_amount / risk_per_share).floor

        if @instrument.lot_size && @instrument.lot_size > 1
          quantity = (quantity / @instrument.lot_size) * @instrument.lot_size
        end

        [quantity, 1].max
      end
    end
  end
end
