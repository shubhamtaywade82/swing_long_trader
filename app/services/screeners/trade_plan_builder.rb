# frozen_string_literal: true

module Screeners
  # Generates actionable trade plan: Entry, SL, TP, RR, Quantity
  # This is what makes a screener result tradeable
  class TradePlanBuilder < ApplicationService
    DEFAULT_RISK_PCT = 0.75 # 0.75% of capital per trade
    MIN_RR = 2.0 # Minimum risk-reward ratio
    DEFAULT_TP_MULTIPLE = 2.5 # Target = Entry + (Risk * 2.5)

    def self.call(candidate:, daily_series:, indicators:, setup_status:, portfolio: nil)
      new(
        candidate: candidate,
        daily_series: daily_series,
        indicators: indicators,
        setup_status: setup_status,
        portfolio: portfolio,
      ).call
    end

    def initialize(candidate:, daily_series:, indicators:, setup_status:, portfolio: nil) # rubocop:disable Lint/MissingSuper
      @candidate = candidate
      @daily_series = daily_series
      @indicators = indicators
      @setup_status = setup_status
      @portfolio = portfolio
      @config = AlgoConfig.fetch[:swing_trading] || {}
    end

    def call
      # Only generate trade plan for READY setups
      return nil unless @setup_status[:status] == SetupDetector::READY

      latest_close = @indicators[:latest_close] || @daily_series.candles.last&.close
      ema20 = @indicators[:ema20]
      ema50 = @indicators[:ema50]
      atr = @indicators[:atr]

      return nil unless latest_close && ema20 && atr

      # Calculate entry price
      entry_price = calculate_entry_price(latest_close, ema20, ema50)

      # Calculate stop loss
      stop_loss = calculate_stop_loss(entry_price, ema20, ema50, atr)

      # Calculate take profit
      take_profit = calculate_take_profit(entry_price, stop_loss, atr)

      # Calculate risk per share
      risk_per_share = (entry_price - stop_loss).abs

      # Calculate risk-reward ratio
      reward = (take_profit - entry_price).abs
      risk_reward = risk_per_share.positive? ? (reward / risk_per_share).round(2) : 0

      # Reject if RR is too low
      return nil if risk_reward < MIN_RR

      # Calculate quantity based on capital and risk
      quantity_result = calculate_quantity(entry_price, risk_per_share)

      {
        entry_price: entry_price.round(2),
        stop_loss: stop_loss.round(2),
        take_profit: take_profit.round(2),
        risk_reward: risk_reward,
        risk_per_share: risk_per_share.round(2),
        quantity: quantity_result[:quantity],
        capital_used: quantity_result[:capital_used],
        risk_amount: quantity_result[:risk_amount],
        max_capital_pct: quantity_result[:max_capital_pct],
        entry_zone: "#{entry_price.round(2)} - #{(entry_price * 1.02).round(2)}",
        setup_type: determine_setup_type(entry_price, ema20, latest_close),
      }
    end

    private

    def calculate_entry_price(latest_close, ema20, _ema50)
      # If price is near EMA20, use EMA20 as entry
      distance_from_ema20_pct = ((latest_close - ema20) / ema20 * 100).round(2)

      if distance_from_ema20_pct.between?(-2, 2)
        # Near EMA20 - use EMA20 as ideal entry
        ema20
      else
        # Use current price as entry (slightly extended or momentum continuation)
        latest_close
      end
    end

    def calculate_stop_loss(entry_price, _ema20, ema50, atr)
      # Stop loss should be below recent swing low or EMA50, whichever is higher
      swing_low = find_recent_swing_low

      # Use 2 ATR below entry as base stop loss
      atr_stop = entry_price - (atr * 2)

      # Use EMA50 if it's below entry and above ATR stop
      ema50_stop = ema50 && ema50 < entry_price ? ema50 : nil

      # Use swing low if it's the highest (safest stop)
      candidates = [atr_stop, ema50_stop, swing_low].compact
      candidates.max # Use the highest stop (tightest, safest)
    end

    def calculate_take_profit(entry_price, stop_loss, _atr)
      risk = (entry_price - stop_loss).abs

      # Target = Entry + (Risk * 2.5) for 2.5R
      target = entry_price + (risk * DEFAULT_TP_MULTIPLE)

      # Also check for structure-based target (resistance levels)
      structure_target = find_structure_target(entry_price)

      # Use structure target if available and reasonable, otherwise use R-multiple target
      if structure_target && structure_target > entry_price && structure_target <= target * 1.2
        structure_target
      else
        target
      end
    end

    def find_recent_swing_low
      return nil if @daily_series.candles.size < 20

      recent_candles = @daily_series.candles.last(20)
      lows = recent_candles.map(&:low)

      # Find local minima (swing lows)
      swing_lows = []
      (1..(lows.size - 2)).each do |i|
        swing_lows << lows[i] if lows[i] < lows[i - 1] && lows[i] < lows[i + 1]
      end

      swing_lows.min
    end

    def find_structure_target(entry_price)
      # Find resistance levels above entry
      return nil if @daily_series.candles.size < 20

      recent_candles = @daily_series.candles.last(20)
      highs = recent_candles.map(&:high)

      # Find swing highs above entry
      swing_highs = []
      (1..(highs.size - 2)).each do |i|
        swing_highs << highs[i] if highs[i] > highs[i - 1] && highs[i] > highs[i + 1] && highs[i] > entry_price
      end

      # Use nearest resistance above entry
      swing_highs.min
    end

    def calculate_quantity(entry_price, risk_per_share)
      return default_quantity_result(entry_price) unless @portfolio

      # Get available capital
      available_capital = if @portfolio.is_a?(CapitalAllocationPortfolio)
                            @portfolio.available_swing_capital || @portfolio.swing_capital || 0
                          elsif @portfolio.respond_to?(:available_capital)
                            @portfolio.available_capital || 0
                          else
                            0
                          end

      return default_quantity_result(entry_price) if available_capital <= 0

      # Calculate risk per trade (0.75% of capital)
      risk_per_trade = available_capital * (DEFAULT_RISK_PCT / 100.0)

      # Calculate quantity based on risk
      quantity_by_risk = (risk_per_trade / risk_per_share).floor

      # Also limit by max position size (10-15% of capital)
      max_capital_pct = 12.0 # 12% max per position
      max_position_value = available_capital * (max_capital_pct / 100.0)
      quantity_by_capital = (max_position_value / entry_price).floor

      # Use the smaller of the two
      quantity = [quantity_by_risk, quantity_by_capital].min

      # Ensure minimum quantity of 1
      quantity = [quantity, 1].max

      capital_used = (quantity * entry_price).round(2)
      risk_amount = (quantity * risk_per_share).round(2)

      {
        quantity: quantity,
        capital_used: capital_used,
        risk_amount: risk_amount,
        max_capital_pct: ((capital_used / available_capital) * 100).round(2),
      }
    end

    def default_quantity_result(entry_price)
      # Default calculation when no portfolio (for display purposes)
      # Assume 100k capital for calculation
      assumed_capital = 100_000
      risk_per_trade = assumed_capital * (DEFAULT_RISK_PCT / 100.0)
      risk_per_share = @indicators[:atr] ? (@indicators[:atr] * 2) : (entry_price * 0.08)
      quantity = (risk_per_trade / risk_per_share).floor
      quantity = [quantity, 1].max

      {
        quantity: quantity,
        capital_used: (quantity * entry_price).round(2),
        risk_amount: (quantity * risk_per_share).round(2),
        max_capital_pct: 0.0, # Unknown without portfolio
      }
    end

    def determine_setup_type(_entry_price, ema20, latest_close)
      distance_from_ema20_pct = ((latest_close - ema20) / ema20 * 100).round(2)

      if distance_from_ema20_pct.between?(-2, 2)
        "EMA pullback"
      elsif distance_from_ema20_pct.between?(2, 8)
        "Momentum continuation"
      else
        "Trend following"
      end
    end
  end
end
