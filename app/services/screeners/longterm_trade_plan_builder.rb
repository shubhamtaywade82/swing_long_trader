# frozen_string_literal: true

module Screeners
  # Generates long-term accumulation plan: Buy Zone, Invalid Level, Time Horizon, Allocation
  # Long-term is about accumulation zones, not precise entry points
  class LongtermTradePlanBuilder < ApplicationService
    DEFAULT_ALLOCATION_PCT = 5.0 # 5% of long-term capital per position
    MIN_TIME_HORIZON_MONTHS = 6
    MAX_TIME_HORIZON_MONTHS = 24

    def self.call(candidate:, daily_series:, weekly_series:, daily_indicators:, weekly_indicators:, setup_status:,
                  portfolio: nil)
      new(
        candidate: candidate,
        daily_series: daily_series,
        weekly_series: weekly_series,
        daily_indicators: daily_indicators,
        weekly_indicators: weekly_indicators,
        setup_status: setup_status,
        portfolio: portfolio,
      ).call
    end

    def initialize(candidate:, daily_series:, weekly_series:, daily_indicators:, weekly_indicators:, setup_status:, portfolio: nil) # rubocop:disable Lint/MissingSuper
      @candidate = candidate
      @daily_series = daily_series
      @weekly_series = weekly_series
      @daily_indicators = daily_indicators
      @weekly_indicators = weekly_indicators
      @setup_status = setup_status
      @portfolio = portfolio
      @config = AlgoConfig.fetch[:long_term_trading] || {}
    end

    def call
      # Only generate plan for ACCUMULATE setups
      return nil unless @setup_status[:status] == LongtermSetupDetector::ACCUMULATE

      # Safely extract numeric values from indicators
      weekly_close = extract_numeric(@weekly_indicators[:latest_close]) || @weekly_series.candles.last&.close
      weekly_ema20 = extract_numeric(@weekly_indicators[:ema20])
      weekly_ema50 = extract_numeric(@weekly_indicators[:ema50])
      weekly_ema200 = extract_numeric(@weekly_indicators[:ema200])
      weekly_atr = extract_numeric(@weekly_indicators[:atr])

      return nil unless weekly_close && weekly_ema20 && weekly_ema50 && weekly_atr

      # Ensure all values are numeric (double-check to prevent Hash/String issues)
      weekly_close = ensure_numeric(weekly_close)
      weekly_ema20 = ensure_numeric(weekly_ema20)
      weekly_ema50 = ensure_numeric(weekly_ema50)
      weekly_atr = ensure_numeric(weekly_atr)
      weekly_ema200 = ensure_numeric(weekly_ema200) if weekly_ema200

      # Validate we have numeric values
      unless weekly_close.is_a?(Numeric) && weekly_ema20.is_a?(Numeric) && weekly_ema50.is_a?(Numeric) && weekly_atr.is_a?(Numeric)
        return nil
      end

      # Calculate accumulation zone (buy range)
      buy_zone = calculate_buy_zone(weekly_close, weekly_ema20, weekly_ema50)

      # Calculate invalid level (structural failure point)
      invalid_level = calculate_invalid_level(weekly_ema50, weekly_ema200, weekly_atr)

      # Calculate time horizon based on trend strength and structure
      time_horizon = calculate_time_horizon(weekly_atr, @weekly_indicators[:adx])

      # Calculate allocation percentage
      allocation_result = calculate_allocation(weekly_close, buy_zone, invalid_level)

      # Calculate add-on zones (averaging points)
      add_on_zones = calculate_add_on_zones(buy_zone, weekly_ema20, weekly_ema50)

      {
        buy_zone: buy_zone,
        invalid_level: invalid_level.round(2),
        time_horizon: time_horizon,
        allocation_pct: allocation_result[:allocation_pct],
        allocation_amount: allocation_result[:allocation_amount],
        add_on_zones: add_on_zones,
        current_price: weekly_close.round(2),
        setup_type: determine_setup_type(weekly_close, weekly_ema20, weekly_ema50),
      }
    end

    private

    def calculate_buy_zone(weekly_close, weekly_ema20, weekly_ema50)
      # Ensure all values are numeric before calculation
      weekly_close = ensure_numeric(weekly_close)
      weekly_ema20 = ensure_numeric(weekly_ema20)
      weekly_ema50 = ensure_numeric(weekly_ema50)

      # Validate numeric values
      unless weekly_close.is_a?(Numeric) && weekly_ema20.is_a?(Numeric) && weekly_ema50.is_a?(Numeric)
        return "#{weekly_close.round(2)} - #{weekly_close.round(2)}"
      end

      # Buy zone is typically EMA20 to EMA50 range, or current price ± 3%
      distance_from_ema20_pct = ((weekly_close - weekly_ema20) / weekly_ema20 * 100).round(2)

      if distance_from_ema20_pct.between?(-5, 5)
        # Near EMA20 - use EMA20 to EMA50 range
        lower = [weekly_ema20, weekly_ema50].min
        upper = [weekly_ema20, weekly_ema50].max
        "#{lower.round(2)} - #{upper.round(2)}"
      elsif distance_from_ema20_pct.between?(5, 10)
        # Slightly above EMA20 - use current price ± 3%
        lower = (weekly_close * 0.97).round(2)
        upper = (weekly_close * 1.03).round(2)
        "#{lower} - #{upper}"
      else
        # Use EMA20 ± 5% as accumulation zone
        lower = (weekly_ema20 * 0.95).round(2)
        upper = (weekly_ema20 * 1.05).round(2)
        "#{lower} - #{upper}"
      end
    end

    def calculate_invalid_level(weekly_ema50, weekly_ema200, weekly_atr)
      # Ensure all values are numeric
      weekly_ema50 = ensure_numeric(weekly_ema50)
      weekly_ema200 = ensure_numeric(weekly_ema200) if weekly_ema200
      weekly_atr = ensure_numeric(weekly_atr)

      # Validate required numeric values
      return weekly_ema50.to_f unless weekly_ema50.is_a?(Numeric) && weekly_atr.is_a?(Numeric)

      # Invalid level is below EMA50 or EMA200, whichever is higher
      # Use 2 ATR below EMA50 as safety margin
      atr_stop = weekly_ema50 - (weekly_atr * 2)

      # Use EMA200 if it's below EMA50 and is numeric
      ema200_stop = if weekly_ema200 && weekly_ema200.is_a?(Numeric) && weekly_ema200 < weekly_ema50
                      weekly_ema200
                    else
                      nil
                    end

      # Use the higher of the two (tighter stop)
      [atr_stop, ema200_stop].compact.max || weekly_ema50
    end

    def calculate_time_horizon(weekly_atr, _weekly_adx)
      # Time horizon based on trend strength and volatility
      # Strong trend (ADX > 25) = shorter horizon (6-12 months)
      # Weak trend (ADX < 25) = longer horizon (12-24 months)
      # High volatility = longer horizon

      # Ensure numeric values
      weekly_atr = ensure_numeric(weekly_atr)
      weekly_adx = extract_numeric(_weekly_adx)

      # Validate weekly_atr is numeric
      return MIN_TIME_HORIZON_MONTHS unless weekly_atr.is_a?(Numeric)

      base_months = if weekly_adx && weekly_adx > 25
                      9 # Strong trend: 9-15 months
                    else
                      15 # Weak trend: 15-24 months
                    end

      # Adjust for volatility (higher ATR = longer horizon)
      volatility_factor = weekly_atr > 0 ? [weekly_atr / 100, 1.5].min : 1.0
      adjusted_months = (base_months * volatility_factor).round

      # Clamp to min/max
      [[adjusted_months, MIN_TIME_HORIZON_MONTHS].max, MAX_TIME_HORIZON_MONTHS].min
    end

    def calculate_allocation(_weekly_close, buy_zone, invalid_level) # weekly_close not used, we parse from buy_zone
      # Parse buy zone to get average buy price
      zone_parts = buy_zone.split(" - ").map(&:to_f)
      avg_buy_price = zone_parts.sum / zone_parts.size

      # Calculate risk per share
      risk_per_share = (avg_buy_price - invalid_level).abs

      return { allocation_pct: DEFAULT_ALLOCATION_PCT, allocation_amount: 0 } unless @portfolio

      # Get available long-term capital
      available_capital = if @portfolio.is_a?(CapitalAllocationPortfolio)
                            @portfolio.available_long_term_capital || @portfolio.long_term_capital || 0
                          elsif @portfolio.respond_to?(:available_capital)
                            @portfolio.available_capital || 0
                          else
                            0
                          end

      return { allocation_pct: DEFAULT_ALLOCATION_PCT, allocation_amount: 0 } if available_capital <= 0

      # Calculate allocation amount (5% of capital)
      allocation_amount = available_capital * (DEFAULT_ALLOCATION_PCT / 100.0)

      # Calculate quantity based on allocation
      quantity = (allocation_amount / avg_buy_price).floor
      quantity = [quantity, 1].max

      {
        allocation_pct: DEFAULT_ALLOCATION_PCT,
        allocation_amount: allocation_amount.round(2),
        quantity: quantity,
        risk_per_share: risk_per_share.round(2),
      }
    end

    def calculate_add_on_zones(_buy_zone, weekly_ema20, weekly_ema50) # buy_zone not used, we use EMA levels
      # Ensure numeric values
      weekly_ema20 = ensure_numeric(weekly_ema20)
      weekly_ema50 = ensure_numeric(weekly_ema50) if weekly_ema50

      # Add-on zones are typically at EMA20, EMA50, and below
      zones = []

      # Zone 1: EMA20 (if not already in buy zone)
      if weekly_ema20 && weekly_ema20.is_a?(Numeric)
        zones << { level: weekly_ema20.round(2), description: "EMA20 support" }
      end

      # Zone 2: EMA50 (if below EMA20)
      if weekly_ema50 && weekly_ema50.is_a?(Numeric) && weekly_ema20 && weekly_ema20.is_a?(Numeric) && weekly_ema50 < weekly_ema20
        zones << { level: weekly_ema50.round(2), description: "EMA50 support" }
      end

      # Zone 3: 5% below EMA20 (if strong pullback)
      if weekly_ema20 && weekly_ema20.is_a?(Numeric)
        zones << { level: (weekly_ema20 * 0.95).round(2), description: "Deep pullback" }
      end

      zones
    end

    def determine_setup_type(_weekly_close, weekly_ema20, weekly_ema50)
      # Ensure numeric values
      weekly_ema20 = ensure_numeric(weekly_ema20)
      weekly_ema50 = ensure_numeric(weekly_ema50) if weekly_ema50

      # Determine setup type for long-term
      if weekly_ema20 && weekly_ema20.is_a?(Numeric) && weekly_ema50 && weekly_ema50.is_a?(Numeric) && weekly_ema20 > weekly_ema50
        "Weekly EMA pullback"
      else
        "Weekly trend continuation"
      end
    end

    def extract_numeric(value)
      return nil if value.nil?
      return value if value.is_a?(Numeric)
      return nil if value.is_a?(Hash) || value.is_a?(Array)
      return value.to_f if value.is_a?(String) && value.match?(/^-?\d+\.?\d*$/)

      # Try to convert to float (handles BigDecimal, etc.)
      return value.to_f if value.respond_to?(:to_f)

      nil
    rescue StandardError => e
      Rails.logger.warn("[LongtermTradePlanBuilder] Failed to extract numeric from #{value.class}: #{e.message}")
      nil
    end

    def ensure_numeric(value)
      return nil if value.nil?
      return value if value.is_a?(Numeric)
      return nil if value.is_a?(Hash) || value.is_a?(Array)

      # Try to convert
      numeric_value = extract_numeric(value)
      return numeric_value if numeric_value

      # Last resort: try direct conversion
      value.to_f if value.respond_to?(:to_f)
    rescue StandardError => e
      Rails.logger.warn("[LongtermTradePlanBuilder] Failed to ensure numeric from #{value.class}: #{e.message}")
      nil
    end
  end
end
