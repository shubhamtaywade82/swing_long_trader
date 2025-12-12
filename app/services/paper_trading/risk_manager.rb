# frozen_string_literal: true

module PaperTrading
  # Manages risk limits for paper trading
  class RiskManager < ApplicationService
    def self.check_limits(portfolio:, signal:)
      new(portfolio: portfolio, signal: signal).check_limits
    end

    def initialize(portfolio:, signal:)
      @portfolio = portfolio
      @signal = signal
      @risk_config = AlgoConfig.fetch(:risk) || {}
    end

    def check_limits
      checks = [
        check_capital_available,
        check_max_position_size,
        check_max_total_exposure,
        check_max_open_positions,
        check_daily_loss_limit,
        check_drawdown_limit,
      ]

      failed_check = checks.find { |check| !check[:success] }
      return failed_check if failed_check

      { success: true }
    end

    private

    def check_capital_available
      entry_price = @signal[:entry_price]
      quantity = @signal[:qty]
      required_capital = entry_price * quantity

      if required_capital > @portfolio.available_capital
        return {
          success: false,
          error: "Insufficient capital: ₹#{required_capital.round(2)} required, ₹#{@portfolio.available_capital.round(2)} available",
        }
      end

      { success: true }
    end

    def check_max_position_size
      max_pct = @risk_config[:max_position_size_pct] || 10.0
      max_value = (@portfolio.capital * max_pct / 100.0)
      order_value = @signal[:entry_price] * @signal[:qty]

      if order_value > max_value
        return {
          success: false,
          error: "Order exceeds max position size: ₹#{order_value.round(2)} > ₹#{max_value.round(2)} (#{max_pct}%)",
        }
      end

      { success: true }
    end

    def check_max_total_exposure
      max_pct = @risk_config[:max_total_exposure_pct] || 50.0
      current_exposure = @portfolio.total_exposure
      new_exposure = @signal[:entry_price] * @signal[:qty]
      total_exposure = current_exposure + new_exposure
      max_value = (@portfolio.capital * max_pct / 100.0)

      if total_exposure > max_value
        return {
          success: false,
          error: "Total exposure exceeds limit: ₹#{total_exposure.round(2)} > ₹#{max_value.round(2)} (#{max_pct}%)",
        }
      end

      { success: true }
    end

    def check_max_open_positions
      max_positions = @risk_config[:max_open_positions] || 5
      current_open = @portfolio.open_positions.count

      if current_open >= max_positions
        return {
          success: false,
          error: "Max open positions reached: #{current_open}/#{max_positions}",
        }
      end

      { success: true }
    end

    def check_daily_loss_limit
      max_daily_loss_pct = @risk_config[:max_daily_loss_pct] || 5.0
      max_daily_loss = (@portfolio.capital * max_daily_loss_pct / 100.0)
      today_loss = calculate_today_loss

      if today_loss.abs > max_daily_loss
        return {
          success: false,
          error: "Daily loss limit exceeded: ₹#{today_loss.abs.round(2)} > ₹#{max_daily_loss.round(2)} (#{max_daily_loss_pct}%)",
        }
      end

      { success: true }
    end

    def check_drawdown_limit
      max_drawdown_pct = @risk_config[:max_drawdown_pct] || 20.0
      current_drawdown = @portfolio.max_drawdown

      if current_drawdown > max_drawdown_pct
        return {
          success: false,
          error: "Max drawdown exceeded: #{current_drawdown.round(2)}% > #{max_drawdown_pct}%",
        }
      end

      { success: true }
    end

    def calculate_today_loss
      today_start = Time.current.beginning_of_day
      today_ledgers = @portfolio.paper_ledgers.where(created_at: today_start..)
      today_credits = today_ledgers.credits.sum(:amount)
      today_debits = today_ledgers.debits.sum(:amount)
      today_credits - today_debits
    end
  end
end
