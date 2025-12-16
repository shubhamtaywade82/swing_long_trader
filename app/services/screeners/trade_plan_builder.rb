# frozen_string_literal: true

module Screeners
  # Generates actionable trade plan: Entry, SL, TP, RR, Quantity
  # This is what makes a screener result tradeable
  class TradePlanBuilder < ApplicationService
    # STRICT RISK MANAGEMENT RULES (as per user requirements)
    DAILY_RISK_PCT = 2.0 # 2% of capital per day (max)
    MAX_TRADES_PER_DAY = 2 # Maximum trades per day
    MIN_RR = 3.0 # Minimum risk-reward ratio (1:3 = 3.0)
    # ATR-based take profit multiples
    TP1_ATR_MULTIPLE = 2.0 # TP1 = Entry + (ATR × 2)
    TP2_ATR_MULTIPLE = 4.0 # TP2 = Entry + (ATR × 4)
    # ATR stop loss multipliers based on volatility
    ATR_SL_LOW_VOL = 1.5 # Low volatility: ATR % < 2%
    ATR_SL_MED_VOL = 2.0 # Medium volatility: ATR % 2-5%
    ATR_SL_HIGH_VOL = 2.5 # High volatility: ATR % > 5%

    # Risk per trade = Daily Risk / Number of trades
    # For 1 trade: 2% / 1 = 2%
    # For 2 trades: 2% / 2 = 1% each
    def self.risk_per_trade_pct(trades_today: 1)
      [DAILY_RISK_PCT / [trades_today, MAX_TRADES_PER_DAY].min, DAILY_RISK_PCT].min
    end

    def self.call(candidate:, daily_series:, indicators:, setup_status:, portfolio: nil, current_ltp: nil)
      new(
        candidate: candidate,
        daily_series: daily_series,
        indicators: indicators,
        setup_status: setup_status,
        portfolio: portfolio,
        current_ltp: current_ltp,
      ).call
    end

    def initialize(candidate:, daily_series:, indicators:, setup_status:, portfolio: nil, current_ltp: nil) # rubocop:disable Lint/MissingSuper
      @candidate = candidate
      @daily_series = daily_series
      @indicators = indicators
      @setup_status = setup_status
      @portfolio = portfolio
      @current_ltp = current_ltp
      @config = AlgoConfig.fetch[:swing_trading] || {}
    end

    def call
      # Only generate trade plan for READY setups
      return nil unless @setup_status[:status] == SetupDetector::READY

      # Get latest candle OHLC data
      latest_candle = @daily_series.latest_candle
      return nil unless latest_candle

      latest_close = @indicators[:latest_close] || latest_candle.close
      latest_high = latest_candle.high
      latest_low = latest_candle.low
      latest_open = latest_candle.open

      ema20 = @indicators[:ema20]
      ema50 = @indicators[:ema50]
      atr = @indicators[:atr]

      return nil unless latest_close && ema20 && atr

      # Use current LTP if available and reasonable, otherwise use latest_close
      # Current LTP is more accurate for entry price calculation
      current_price = get_current_price(latest_close)

      # Calculate entry price using LTP, OHLC data, and indicators
      entry_price = calculate_entry_price(current_price, latest_high, latest_low, latest_open, latest_close, ema20,
                                          ema50)

      # Calculate ATR percentage for volatility classification
      atr_pct = (atr / latest_close * 100).round(2)

      # Calculate stop loss with dynamic ATR multiplier based on volatility
      stop_loss = calculate_stop_loss(entry_price, ema20, ema50, atr, atr_pct)

      # Calculate take profit targets (TP1 and TP2) using ATR multiples
      take_profit_result = calculate_take_profit_atr(entry_price, atr, stop_loss)

      # Calculate risk per share
      risk_per_share = (entry_price - stop_loss).abs

      # Calculate risk-reward ratio based on TP2 (final target)
      reward = (take_profit_result[:tp2] - entry_price).abs
      risk_reward = risk_per_share.positive? ? (reward / risk_per_share).round(2) : 0

      # Reject if RR is too low (based on TP2)
      return nil if risk_reward < MIN_RR

      # Calculate quantity based on capital and risk
      quantity_result = calculate_quantity(entry_price, risk_per_share)

      {
        entry_price: entry_price.round(2),
        stop_loss: stop_loss.round(2),
        take_profit: take_profit_result[:tp2].round(2), # TP2 is the final target
        tp1: take_profit_result[:tp1].round(2),
        tp2: take_profit_result[:tp2].round(2),
        atr: atr.round(2),
        atr_pct: atr_pct,
        atr_sl_multiplier: take_profit_result[:atr_sl_multiplier],
        risk_reward: risk_reward,
        risk_per_share: risk_per_share.round(2),
        quantity: quantity_result[:quantity],
        capital_used: quantity_result[:capital_used],
        risk_amount: quantity_result[:risk_amount],
        max_capital_pct: quantity_result[:max_capital_pct],
        entry_zone: calculate_entry_zone(entry_price, latest_high, latest_low, current_price, latest_candle),
        setup_type: determine_setup_type(entry_price, ema20, current_price),
      }
    end

    private

    # Get current price: prefer current LTP if available and reasonable, otherwise use latest_close
    def get_current_price(latest_close)
      return latest_close unless @current_ltp&.positive?

      # Use current LTP if it's within 50% of latest_close (to avoid using obviously incorrect data)
      # This allows for legitimate market movements while filtering out data errors
      price_diff_pct = ((@current_ltp - latest_close) / latest_close * 100).abs
      if price_diff_pct <= 50.0
        # Log if difference is significant but still reasonable (for monitoring)
        if price_diff_pct > 10.0
          Rails.logger.info(
            "[Screeners::TradePlanBuilder] Using current LTP (#{@current_ltp}) which differs " \
            "#{price_diff_pct.round(2)}% from latest_close (#{latest_close}) for entry calculation",
          )
        end
        @current_ltp
      else
        # If LTP is extremely far from latest_close, it might be stale or incorrect
        # Log warning and use latest_close
        Rails.logger.warn(
          "[Screeners::TradePlanBuilder] Current LTP (#{@current_ltp}) differs too much " \
          "(#{price_diff_pct.round(2)}%) from latest_close (#{latest_close}), using latest_close for entry calculation",
        )
        latest_close
      end
    end

    def calculate_entry_price(current_price, latest_high, latest_low, _latest_open, _latest_close, ema20, ema50)
      # Entry price calculation based on LTP, OHLC data, and indicators
      # Priority: LTP > Latest Close > EMA20 > EMA50

      # Use current LTP (real-time price) as base
      base_price = current_price

      # Calculate distance from EMA20
      distance_from_ema20_pct = ((base_price - ema20) / ema20 * 100).round(2)

      # Strategy 1: If price is near EMA20 (within 2%), use EMA20 as ideal entry
      return ema20 if distance_from_ema20_pct.between?(-2, 2)

      # Strategy 2: If price is below EMA20 but above EMA50, use lower of LTP or latest low
      # This captures pullback entries
      if base_price < ema20 && (!ema50 || base_price > ema50)
        # Use the lower of current LTP or latest candle low for better entry
        return [base_price, latest_low].min
      end

      # Strategy 3: If price is above EMA20, consider using latest high for breakout entries
      # But prefer current LTP if it's reasonable
      if base_price > ema20
        # For momentum continuation, use current LTP
        # But if LTP is significantly above latest high, use latest high + small buffer
        if base_price > latest_high * 1.02
          # LTP is too extended, use latest high with small buffer
          return latest_high * 1.005
        end

        return base_price
      end

      # Strategy 4: Default to current LTP, but ensure it's within reasonable range of OHLC
      # If LTP is outside the day's range, use the closer boundary
      if base_price > latest_high
        # LTP above day's high - use high with small buffer for breakout
        latest_high * 1.005
      elsif base_price < latest_low
        # LTP below day's low - use low for pullback entry
        latest_low
      else
        # LTP within day's range - use LTP
        base_price
      end
    end

    def calculate_stop_loss(entry_price, _ema20, ema50, atr, atr_pct)
      # Determine ATR multiplier based on volatility
      # Low volatility: ATR % < 2% → Use 1.5× ATR
      # Medium volatility: ATR % 2-5% → Use 2.0× ATR
      # High volatility: ATR % > 5% → Use 2.5× ATR
      atr_multiplier = if atr_pct < 2.0
                         ATR_SL_LOW_VOL
                       elsif atr_pct <= 5.0
                         ATR_SL_MED_VOL
                       else
                         ATR_SL_HIGH_VOL
                       end

      # Stop loss should be below recent swing low (from OHLC data) or EMA50, whichever is higher
      swing_low = find_recent_swing_low

      # Also consider latest candle's low as a potential stop level
      latest_candle = @daily_series.latest_candle
      latest_low = latest_candle&.low

      # Use dynamic ATR multiplier below entry as base stop loss
      atr_stop = entry_price - (atr * atr_multiplier)

      # Use EMA50 if it's below entry and above ATR stop
      ema50_stop = ema50 && ema50 < entry_price ? ema50 : nil

      # Consider latest candle low if it's below entry and reasonable
      # This uses actual OHLC data for stop placement
      candle_low_stop = (latest_low if latest_low && latest_low < entry_price && latest_low > atr_stop)

      # Use swing low if it's the highest (safest stop)
      # Swing low comes from actual OHLC data (candle lows)
      candidates = [atr_stop, ema50_stop, candle_low_stop, swing_low].compact
      final_stop = candidates.max # Use the highest stop (tightest, safest)

      # Store ATR multiplier in result for reference
      @atr_sl_multiplier_used = atr_multiplier

      final_stop
    end

    def calculate_take_profit_atr(entry_price, atr, _stop_loss)
      # Calculate TP1 and TP2 using ATR multiples (as per requirements)
      # TP1 = Entry + (ATR × 2)
      # TP2 = Entry + (ATR × 4)
      tp1 = entry_price + (atr * TP1_ATR_MULTIPLE)
      tp2 = entry_price + (atr * TP2_ATR_MULTIPLE)

      # Also check for structure-based targets (resistance levels)
      structure_target = find_structure_target(entry_price)

      # Adjust TP1 if structure target is reasonable
      if structure_target && structure_target > entry_price && structure_target <= tp1 * 1.1
        tp1 = [tp1, structure_target].min # Use lower of ATR-based or structure-based
      end

      # Adjust TP2 if structure target is reasonable and higher than TP1
      if structure_target && structure_target > tp1 && structure_target <= tp2 * 1.2
        tp2 = [tp2, structure_target].min # Use lower of ATR-based or structure-based
      end

      {
        tp1: tp1,
        tp2: tp2,
        atr_sl_multiplier: @atr_sl_multiplier_used || ATR_SL_MED_VOL,
      }
    end

    def find_recent_swing_low
      return nil if @daily_series.candles.size < 20

      # Get recent candles sorted by timestamp (most recent last)
      recent_candles = @daily_series.candles.sort_by(&:timestamp).last(20)
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

      # Get recent candles sorted by timestamp (most recent last)
      recent_candles = @daily_series.candles.sort_by(&:timestamp).last(20)
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

      # Calculate risk per trade based on daily risk limit and number of trades today
      # Daily risk = 2% of capital, split by number of trades (1-2 trades per day)
      trades_today = count_trades_today
      risk_per_trade_pct = self.class.risk_per_trade_pct(trades_today: trades_today)
      risk_per_trade = available_capital * (risk_per_trade_pct / 100.0)

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

    def count_trades_today
      return 1 unless @portfolio # Default to 1 trade if no portfolio

      today = Date.current
      if @portfolio.is_a?(CapitalAllocationPortfolio)
        @portfolio.open_swing_positions
                  .where("created_at >= ?", today.beginning_of_day)
                  .count
      elsif @portfolio.respond_to?(:open_positions)
        @portfolio.open_positions
                  .where("opened_at >= ?", today.beginning_of_day)
                  .count
      else
        1
      end
    end

    def default_quantity_result(entry_price)
      # Default calculation when no portfolio (for display purposes)
      # Assume 100k capital for calculation
      assumed_capital = 100_000
      # Use 2% daily risk, assume 1 trade today
      risk_per_trade_pct = self.class.risk_per_trade_pct(trades_today: 1)
      risk_per_trade = assumed_capital * (risk_per_trade_pct / 100.0)
      # Use dynamic ATR multiplier for default calculation
      atr = @indicators[:atr]
      if atr
        atr_pct = (atr / entry_price * 100).round(2)
        atr_multiplier = if atr_pct < 2.0
                           ATR_SL_LOW_VOL
                         elsif atr_pct <= 5.0
                           ATR_SL_MED_VOL
                         else
                           ATR_SL_HIGH_VOL
                         end
        risk_per_share = atr * atr_multiplier
      else
        risk_per_share = entry_price * 0.08
      end
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
