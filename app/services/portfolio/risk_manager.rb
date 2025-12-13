# frozen_string_literal: true

module Portfolio
  class RiskManager < ApplicationService
    def initialize(portfolio:)
      @portfolio = portfolio
      @risk_config = portfolio.swing_risk_config
    end

    def call
      checks = {
        daily_loss_check: check_daily_loss,
        max_positions_check: check_max_positions,
        drawdown_check: check_drawdown,
        consecutive_losses_check: check_consecutive_losses,
      }

      all_passed = checks.values.all?
      reasons = checks.select { |_, passed| !passed }.keys

      {
        allowed: all_passed,
        checks: checks,
        reasons: reasons,
      }
    end

    def can_open_new_position?
      result = call
      result[:allowed]
    end

    def check_daily_loss
      # Calculate today's realized P&L from closed positions
      today_closed = @portfolio.closed_swing_positions
                                .where("closed_at >= ?", Time.current.beginning_of_day)

      daily_loss = today_closed.sum(&:realized_pnl)
      daily_loss_pct = @portfolio.total_equity > 0 ? (daily_loss.abs / @portfolio.total_equity * 100).round(2) : 0

      max_daily_risk_pct = @risk_config.max_daily_risk

      if daily_loss.negative? && daily_loss_pct >= max_daily_risk_pct
        log_warn("Daily loss limit reached: #{daily_loss_pct}% (limit: #{max_daily_risk_pct}%)")
        return false
      end

      true
    end

    def check_max_positions
      open_count = @portfolio.open_swing_positions.count
      max_allowed = @risk_config.max_open_positions

      if open_count >= max_allowed
        log_warn("Max positions limit reached: #{open_count}/#{max_allowed}")
        return false
      end

      true
    end

    def check_drawdown
      current_dd = @portfolio.max_drawdown
      max_allowed_dd = @risk_config.max_portfolio_dd

      if current_dd >= max_allowed_dd
        log_error("Max drawdown limit reached: #{current_dd}% (limit: #{max_allowed_dd}%)")
        notify("🚨 MAX DRAWDOWN LIMIT REACHED\n\nPortfolio: #{@portfolio.name}\nDrawdown: #{current_dd}%\nLimit: #{max_allowed_dd}%\n\nConsider switching to paper mode.", tag: "RISK_LIMIT")
        return false
      end

      true
    end

    def check_consecutive_losses
      recent_closed = @portfolio.closed_swing_positions
                                .order(closed_at: :desc)
                                .limit(2)

      return true if recent_closed.count < 2

      consecutive_losses = recent_closed.all? { |pos| (pos.realized_pnl || 0).negative? }

      if consecutive_losses
        log_warn("2 consecutive losses detected - cooldown period activated")
        return false
      end

      true
    end

    def daily_loss_exceeded?
      !check_daily_loss
    end

    def max_positions_reached?
      !check_max_positions
    end

    def drawdown_exceeded?
      !check_drawdown
    end

    def consecutive_losses_detected?
      !check_consecutive_losses
    end
  end
end
