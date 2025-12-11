# frozen_string_literal: true

require 'csv'

module Backtesting
  # Generates reports from backtest results
  class ReportGenerator
    def self.generate(backtest_run)
      new(backtest_run).generate_all
    end

    def initialize(backtest_run)
      @backtest_run = backtest_run
      @positions = backtest_run.backtest_positions.order(:entry_date)
    end

    def generate_all
      {
        summary: generate_summary,
        trades_csv: generate_trades_csv,
        equity_curve_csv: generate_equity_curve_csv,
        metrics_report: generate_metrics_report,
        visualization_data: generate_visualization_data
      }
    end

    def generate_summary
      <<~SUMMARY
        Backtest Run Summary
        ====================

        Strategy: #{@backtest_run.strategy_name}
        Period: #{@backtest_run.start_date} to #{@backtest_run.end_date}
        Initial Capital: ₹#{@backtest_run.initial_capital.to_fs(:delimited)}
        Final Capital: ₹#{@backtest_run.final_capital.to_fs(:delimited)}

        Performance Metrics:
        - Total Return: #{@backtest_run.total_return.round(2)}%
        - Annualized Return: #{@backtest_run.annualized_return.round(2)}%
        - Max Drawdown: #{@backtest_run.max_drawdown.round(2)}%
        - Sharpe Ratio: #{@backtest_run.sharpe_ratio.round(4)}
        - Sortino Ratio: #{@backtest_run.sortino_ratio.round(4)}

        Trade Statistics:
        - Total Trades: #{@backtest_run.total_trades}
        - Win Rate: #{@backtest_run.win_rate.round(2)}%
        - Profit Factor: #{@backtest_run.profit_factor.round(2)}
        - Best Trade: ₹#{@backtest_run.metrics&.dig('best_trade', 'pnl')&.round(2) || 'N/A'}
        - Worst Trade: ₹#{@backtest_run.metrics&.dig('worst_trade', 'pnl')&.round(2) || 'N/A'}

        Generated: #{Time.current}
      SUMMARY
    end

    def generate_trades_csv
      CSV.generate(headers: true) do |csv|
        csv << %w[Symbol Direction EntryDate EntryPrice ExitDate ExitPrice Quantity PnL PnL_Pct HoldingDays ExitReason]

        @positions.each do |position|
          symbol = position.instrument&.symbol_name || 'N/A'
          csv << [
            symbol,
            position.direction,
            position.entry_date,
            position.entry_price.to_f,
            position.exit_date,
            position.exit_price.to_f,
            position.quantity,
            position.pnl.to_f,
            position.pnl_pct.to_f,
            position.holding_days,
            position.exit_reason
          ]
        end
      end
    end

    def generate_equity_curve_csv
      # Generate equity curve from positions
      equity_curve = build_equity_curve

      CSV.generate(headers: true) do |csv|
        csv << %w[Date Equity Drawdown]

        equity_curve.each do |point|
          csv << [
            point[:date],
            point[:equity].round(2),
            point[:drawdown].round(2)
          ]
        end
      end
    end

    def generate_metrics_report
      metrics = @backtest_run.metrics || {}

      <<~METRICS
        Detailed Performance Metrics
        ============================

        Returns:
        - Total Return: #{@backtest_run.total_return.round(2)}%
        - Annualized Return: #{@backtest_run.annualized_return.round(2)}%

        Risk Metrics:
        - Maximum Drawdown: #{@backtest_run.max_drawdown.round(2)}%
        - Sharpe Ratio: #{@backtest_run.sharpe_ratio.round(4)}
        - Sortino Ratio: #{@backtest_run.sortino_ratio.round(4)}

        Trade Analysis:
        - Total Trades: #{@backtest_run.total_trades}
        - Winning Trades: #{metrics['winning_trades'] || 0}
        - Losing Trades: #{metrics['losing_trades'] || 0}
        - Win Rate: #{@backtest_run.win_rate.round(2)}%
        - Average Win/Loss Ratio: #{metrics['avg_win_loss_ratio']&.round(2) || 'N/A'}
        - Profit Factor: #{@backtest_run.profit_factor.round(2)}
        - Average Holding Period: #{metrics['avg_holding_period']&.round(1) || 'N/A'} days

        Trade Extremes:
        - Best Trade: ₹#{metrics.dig('best_trade', 'pnl')&.round(2) || 'N/A'} (#{metrics.dig('best_trade', 'pnl_pct')&.round(2) || 'N/A'}%)
        - Worst Trade: ₹#{metrics.dig('worst_trade', 'pnl')&.round(2) || 'N/A'} (#{metrics.dig('worst_trade', 'pnl_pct')&.round(2) || 'N/A'}%)
        - Consecutive Wins: #{metrics['consecutive_wins'] || 0}
        - Consecutive Losses: #{metrics['consecutive_losses'] || 0}

        Monthly Returns:
        #{format_monthly_returns(metrics['monthly_returns'] || {})}
      METRICS
    end

    def generate_visualization_data
      equity_curve = build_equity_curve
      monthly_returns = calculate_monthly_returns

      {
        equity_curve: equity_curve,
        monthly_returns: monthly_returns,
        trade_distribution: calculate_trade_distribution,
        metrics: {
          total_return: @backtest_run.total_return,
          annualized_return: @backtest_run.annualized_return,
          max_drawdown: @backtest_run.max_drawdown,
          sharpe_ratio: @backtest_run.sharpe_ratio,
          sortino_ratio: @backtest_run.sortino_ratio,
          win_rate: @backtest_run.win_rate,
          profit_factor: @backtest_run.profit_factor
        }
      }
    end

    private

    def build_equity_curve
      return [] if @positions.empty?

      initial_capital = @backtest_run.initial_capital.to_f
      equity = initial_capital
      peak = initial_capital
      curve = []

      # Group positions by date
      positions_by_date = @positions.group_by { |p| p.exit_date || p.entry_date }

      # Sort dates
      dates = positions_by_date.keys.sort

      dates.each do |date|
        # Get all positions closed on this date
        day_positions = positions_by_date[date].select(&:exit_date)

        # Update equity
        day_positions.each do |position|
          equity += position.pnl.to_f
        end

        # Update peak and calculate drawdown
        peak = [peak, equity].max
        drawdown = ((peak - equity) / peak * 100).round(2)

        curve << {
          date: date.to_s,
          equity: equity.round(2),
          drawdown: drawdown
        }
      end

      curve
    end

    def calculate_monthly_returns
      return {} if @positions.empty?

      monthly_pnl = Hash.new(0.0)
      monthly_capital = Hash.new(@backtest_run.initial_capital.to_f)

      @positions.each do |position|
        next unless position.exit_date

        month_key = position.exit_date.strftime('%Y-%m')
        monthly_pnl[month_key] += position.pnl.to_f
      end

      monthly_returns = {}
      monthly_pnl.each do |month, pnl|
        prev_month_capital = monthly_capital[month]
        monthly_returns[month] = {
          pnl: pnl.round(2),
          return_pct: prev_month_capital > 0 ? (pnl / prev_month_capital * 100).round(2) : 0
        }
        monthly_capital[month] = prev_month_capital + pnl
      end

      monthly_returns
    end

    def calculate_trade_distribution
      return {} if @positions.empty?

      {
        by_direction: @positions.group(:direction).count,
        by_exit_reason: @positions.group(:exit_reason).count,
        by_holding_period: {
          '1-5 days' => @positions.where(holding_days: 1..5).count,
          '6-10 days' => @positions.where(holding_days: 6..10).count,
          '11-15 days' => @positions.where(holding_days: 11..15).count,
          '16+ days' => @positions.where('holding_days > 15').count
        },
        pnl_distribution: {
          '> 5%' => @positions.where('pnl_pct > 5').count,
          '2-5%' => @positions.where(pnl_pct: 2..5).count,
          '0-2%' => @positions.where(pnl_pct: 0..2).count,
          '-2-0%' => @positions.where(pnl_pct: -2..0).count,
          '< -2%' => @positions.where('pnl_pct < -2').count
        }
      }
    end

    def format_monthly_returns(monthly_returns)
      return 'No monthly data available' if monthly_returns.empty?

      monthly_returns.map do |month, data|
        "  #{month}: #{data[:return_pct]}% (₹#{data[:pnl]})"
      end.join("\n")
    end
  end
end

