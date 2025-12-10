# frozen_string_literal: true

module Backtesting
  # Analyzes backtest results and calculates performance metrics
  class ResultAnalyzer
    attr_reader :positions, :initial_capital, :final_capital

    def initialize(positions:, initial_capital:, final_capital:)
      @positions = positions
      @initial_capital = initial_capital.to_f
      @final_capital = final_capital.to_f
    end

    def analyze
      {
        total_return: total_return,
        annualized_return: annualized_return,
        max_drawdown: max_drawdown,
        sharpe_ratio: sharpe_ratio,
        sortino_ratio: sortino_ratio,
        win_rate: win_rate,
        avg_win_loss_ratio: avg_win_loss_ratio,
        profit_factor: profit_factor,
        total_trades: total_trades,
        winning_trades: winning_trades,
        losing_trades: losing_trades,
        avg_holding_period: avg_holding_period,
        best_trade: best_trade,
        worst_trade: worst_trade,
        consecutive_wins: consecutive_wins,
        consecutive_losses: consecutive_losses,
        equity_curve: equity_curve_data,
        monthly_returns: monthly_returns
      }
    end

    private

    def total_return
      return 0 if @initial_capital.zero?

      ((@final_capital - @initial_capital) / @initial_capital * 100).round(2)
    end

    def annualized_return(days: nil)
      return 0 if @initial_capital.zero?

      days ||= trading_days
      return 0 if days.zero?

      years = days / 252.0 # Trading days per year
      return 0 if years <= 0

      ((@final_capital / @initial_capital)**(1.0 / years) - 1) * 100
    end

    def max_drawdown
      return 0 if equity_curve_data.empty?

      peak = @initial_capital
      max_dd = 0.0

      equity_curve_data.each do |point|
        equity = point[:equity]
        peak = [peak, equity].max
        drawdown = ((peak - equity) / peak * 100)
        max_dd = [max_dd, drawdown].max
      end

      max_dd.round(2)
    end

    def sharpe_ratio(risk_free_rate: 0.0)
      returns = period_returns
      return 0 if returns.empty?

      avg_return = returns.sum / returns.size
      std_dev = Math.sqrt(returns.map { |r| (r - avg_return)**2 }.sum / returns.size)
      return 0 if std_dev.zero?

      ((avg_return - risk_free_rate) / std_dev * Math.sqrt(252)).round(4)
    end

    def sortino_ratio(risk_free_rate: 0.0)
      returns = period_returns
      return 0 if returns.empty?

      avg_return = returns.sum / returns.size
      downside_returns = returns.select { |r| r < 0 }
      return 0 if downside_returns.empty?

      downside_std = Math.sqrt(downside_returns.map { |r| r**2 }.sum / downside_returns.size)
      return 0 if downside_std.zero?

      ((avg_return - risk_free_rate) / downside_std * Math.sqrt(252)).round(4)
    end

    def win_rate
      return 0 if total_trades.zero?

      (winning_trades.to_f / total_trades * 100).round(2)
    end

    def avg_win_loss_ratio
      wins = winning_trade_pnls
      losses = losing_trade_pnls

      return 0 if wins.empty? || losses.empty?

      avg_win = wins.sum / wins.size
      avg_loss = losses.sum.abs / losses.size
      return 0 if avg_loss.zero?

      (avg_win / avg_loss).round(2)
    end

    def profit_factor
      gross_profit = winning_trade_pnls.sum
      gross_loss = losing_trade_pnls.sum.abs

      return 0 if gross_loss.zero?

      (gross_profit / gross_loss).round(2)
    end

    def total_trades
      @positions.size
    end

    def winning_trades
      @positions.count { |p| p.calculate_pnl > 0 }
    end

    def losing_trades
      @positions.count { |p| p.calculate_pnl < 0 }
    end

    def avg_holding_period
      return 0 if @positions.empty?

      total_days = @positions.sum { |p| p.holding_days }
      (total_days.to_f / @positions.size).round(1)
    end

    def best_trade
      return nil if @positions.empty?

      best = @positions.max_by { |p| p.calculate_pnl }
      {
        pnl: best.calculate_pnl.round(2),
        pnl_pct: best.calculate_pnl_pct.round(2),
        holding_days: best.holding_days
      }
    end

    def worst_trade
      return nil if @positions.empty?

      worst = @positions.min_by { |p| p.calculate_pnl }
      {
        pnl: worst.calculate_pnl.round(2),
        pnl_pct: worst.calculate_pnl_pct.round(2),
        holding_days: worst.holding_days
      }
    end

    def consecutive_wins
      max_consecutive = 0
      current = 0

      @positions.each do |pos|
        if pos.calculate_pnl > 0
          current += 1
          max_consecutive = [max_consecutive, current].max
        else
          current = 0
        end
      end

      max_consecutive
    end

    def consecutive_losses
      max_consecutive = 0
      current = 0

      @positions.each do |pos|
        if pos.calculate_pnl < 0
          current += 1
          max_consecutive = [max_consecutive, current].max
        else
          current = 0
        end
      end

      max_consecutive
    end

    def equity_curve_data
      # This should be populated from portfolio during backtest
      # For now, return empty array - will be implemented in engine
      []
    end

    def monthly_returns
      # Group positions by month and calculate returns
      # This should be populated from portfolio during backtest
      {}
    end

    def trading_days
      return 0 if @positions.empty?

      first_date = @positions.map { |p| p.entry_date }.min
      last_date = @positions.map { |p| p.exit_date || p.entry_date }.max

      return 0 unless first_date && last_date

      (last_date.to_date - first_date.to_date).to_i
    end

    def period_returns
      # Calculate daily returns from equity curve
      # For now, return empty - will be implemented with equity curve
      []
    end

    def winning_trade_pnls
      @positions.select { |p| p.calculate_pnl > 0 }.map { |p| p.calculate_pnl }
    end

    def losing_trade_pnls
      @positions.select { |p| p.calculate_pnl < 0 }.map { |p| p.calculate_pnl }
    end
  end
end

