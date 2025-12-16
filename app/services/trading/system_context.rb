# frozen_string_literal: true

module Trading
  # Read-only snapshot of system state
  # Provides context to Decision Engine to prevent blowups
  # Immutable - represents a point in time
  class SystemContext
    attr_reader :market_regime
    attr_reader :recent_pnl
    attr_reader :drawdown
    attr_reader :open_positions
    attr_reader :time_of_day
    attr_reader :trading_day_stats
    attr_reader :captured_at

    # Market regime types
    REGIME_BULLISH = "bullish"
    REGIME_BEARISH = "bearish"
    REGIME_NEUTRAL = "neutral"
    REGIME_VOLATILE = "volatile"

    def initialize(
      market_regime: REGIME_NEUTRAL,
      recent_pnl: {},
      drawdown: 0.0,
      open_positions: {},
      time_of_day: nil,
      trading_day_stats: {},
      captured_at: Time.current
    )
      @market_regime = market_regime.to_s
      @recent_pnl = recent_pnl.freeze
      @drawdown = drawdown.to_f
      @open_positions = open_positions.freeze
      @time_of_day = time_of_day || determine_time_of_day
      @trading_day_stats = trading_day_stats.freeze
      @captured_at = captured_at
    end

    def bullish_market?
      market_regime == REGIME_BULLISH
    end

    def bearish_market?
      market_regime == REGIME_BEARISH
    end

    def volatile_market?
      market_regime == REGIME_VOLATILE
    end

    def in_drawdown?
      drawdown > 0.0
    end

    def significant_drawdown?(threshold: 10.0)
      drawdown >= threshold
    end

    def market_hours?
      time_of_day == "market_hours"
    end

    def pre_market?
      time_of_day == "pre_market"
    end

    def post_market?
      time_of_day == "post_market"
    end

    def after_hours?
      time_of_day == "after_hours"
    end

    def today_pnl
      recent_pnl[:today] || 0.0
    end

    def week_pnl
      recent_pnl[:week] || 0.0
    end

    def losing_day?
      today_pnl < 0
    end

    def winning_day?
      today_pnl > 0
    end

    def open_positions_count
      open_positions[:count] || 0
    end

    def total_exposure
      open_positions[:total_exposure] || 0.0
    end

    def trades_today
      trading_day_stats[:trades_count] || 0
    end

    def wins_today
      trading_day_stats[:wins_count] || 0
    end

    def losses_today
      trading_day_stats[:losses_count] || 0
    end

    def consecutive_losses
      trading_day_stats[:consecutive_losses] || 0
    end

    def to_hash
      {
        market_regime: market_regime,
        recent_pnl: recent_pnl,
        drawdown: drawdown,
        open_positions: open_positions,
        time_of_day: time_of_day,
        trading_day_stats: trading_day_stats,
        captured_at: captured_at.iso8601,
      }
    end

    # Factory method: Build from portfolio
    def self.from_portfolio(portfolio, market_regime: nil)
      return nil unless portfolio

      # Calculate recent PnL
      recent_pnl = calculate_recent_pnl(portfolio)

      # Calculate drawdown
      drawdown = calculate_drawdown(portfolio)

      # Get open positions stats
      open_positions = calculate_open_positions(portfolio)

      # Get trading day stats
      trading_day_stats = calculate_trading_day_stats(portfolio)

      # Determine market regime if not provided
      market_regime ||= determine_market_regime(portfolio)

      new(
        market_regime: market_regime,
        recent_pnl: recent_pnl,
        drawdown: drawdown,
        open_positions: open_positions,
        trading_day_stats: trading_day_stats,
      )
    end

    # Factory method: Build empty context (for testing or when no portfolio)
    def self.empty
      new(
        market_regime: REGIME_NEUTRAL,
        recent_pnl: {},
        drawdown: 0.0,
        open_positions: { count: 0, total_exposure: 0.0 },
        trading_day_stats: {},
      )
    end

    private

    def determine_time_of_day
      now = Time.current.in_time_zone("Asia/Kolkata")
      return "after_hours" unless now.wday.between?(1, 5) # Mon-Fri

      market_open = now.change(hour: 9, min: 15, sec: 0)
      market_close = now.change(hour: 15, min: 30, sec: 0)
      pre_market_start = now.change(hour: 9, min: 0, sec: 0)

      if now < pre_market_start
        "pre_market"
      elsif now >= market_open && now <= market_close
        "market_hours"
      elsif now > market_close && now.hour < 16
        "post_market"
      else
        "after_hours"
      end
    end

    def self.calculate_recent_pnl(portfolio)
      today = Date.current
      today_start = today.beginning_of_day

      # Get today's realized PnL from closed positions
      closed_today = if portfolio.respond_to?(:closed_swing_positions)
                      portfolio.closed_swing_positions.where("closed_at >= ?", today_start)
                    elsif portfolio.respond_to?(:closed_positions)
                      portfolio.closed_positions.where("closed_at >= ?", today_start)
                    else
                      []
                    end

      today_pnl = closed_today.sum do |pos|
        pos.respond_to?(:realized_pnl) ? pos.realized_pnl.to_f : 0.0
      end

      # Get this week's PnL
      week_start = today.beginning_of_week
      closed_week = if portfolio.respond_to?(:closed_swing_positions)
                     portfolio.closed_swing_positions.where("closed_at >= ?", week_start)
                   elsif portfolio.respond_to?(:closed_positions)
                     portfolio.closed_positions.where("closed_at >= ?", week_start)
                   else
                     []
                   end

      week_pnl = closed_week.sum do |pos|
        pos.respond_to?(:realized_pnl) ? pos.realized_pnl.to_f : 0.0
      end

      {
        today: today_pnl,
        week: week_pnl,
      }
    end

    def self.calculate_drawdown(portfolio)
      return 0.0 unless portfolio.respond_to?(:max_drawdown)

      portfolio.max_drawdown.to_f
    end

    def self.calculate_open_positions(portfolio)
      open_positions = if portfolio.respond_to?(:open_swing_positions)
                        portfolio.open_swing_positions
                      elsif portfolio.respond_to?(:open_positions)
                        portfolio.open_positions
                      else
                        []
                      end

      count = open_positions.count
      total_exposure = open_positions.sum do |pos|
        if pos.respond_to?(:entry_price) && pos.respond_to?(:quantity)
          pos.entry_price.to_f * pos.quantity.to_i
        else
          0.0
        end
      end

      {
        count: count,
        total_exposure: total_exposure.to_f,
      }
    end

    def self.calculate_trading_day_stats(portfolio)
      today = Date.current
      today_start = today.beginning_of_day

      # Get trades closed today
      closed_today = if portfolio.respond_to?(:closed_swing_positions)
                      portfolio.closed_swing_positions.where("closed_at >= ?", today_start).order(closed_at: :desc)
                    elsif portfolio.respond_to?(:closed_positions)
                      portfolio.closed_positions.where("closed_at >= ?", today_start).order(closed_at: :desc)
                    else
                      []
                    end

      trades_count = closed_today.count
      wins = closed_today.select { |pos| (pos.respond_to?(:realized_pnl) ? pos.realized_pnl.to_f : 0.0) > 0 }
      losses = closed_today.select { |pos| (pos.respond_to?(:realized_pnl) ? pos.realized_pnl.to_f : 0.0) < 0 }

      # Calculate consecutive losses (from most recent)
      consecutive_losses = 0
      closed_today.each do |pos|
        pnl = pos.respond_to?(:realized_pnl) ? pos.realized_pnl.to_f : 0.0
        if pnl < 0
          consecutive_losses += 1
        else
          break
        end
      end

      {
        trades_count: trades_count,
        wins_count: wins.count,
        losses_count: losses.count,
        consecutive_losses: consecutive_losses,
      }
    end

    def self.determine_market_regime(portfolio)
      # Simple heuristic: use recent PnL and drawdown
      # Could be enhanced with market index analysis
      recent_pnl = calculate_recent_pnl(portfolio)
      drawdown = calculate_drawdown(portfolio)

      if drawdown > 15.0
        REGIME_VOLATILE
      elsif recent_pnl[:week] > 0 && drawdown < 5.0
        REGIME_BULLISH
      elsif recent_pnl[:week] < 0 && drawdown > 10.0
        REGIME_BEARISH
      else
        REGIME_NEUTRAL
      end
    end
  end
end
