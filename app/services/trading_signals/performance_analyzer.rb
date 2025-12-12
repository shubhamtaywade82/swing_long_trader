# frozen_string_literal: true

module TradingSignals
  # Analyzes performance of executed vs simulated signals
  # Compares what actually happened vs what would have happened
  class PerformanceAnalyzer < ApplicationService
    def self.analyze(signals: nil, compare_executed_vs_simulated: true)
      new(signals: signals, compare_executed_vs_simulated: compare_executed_vs_simulated).analyze
    end

    def initialize(signals: nil, compare_executed_vs_simulated: true)
      @signals = signals || TradingSignal.all
      @compare_executed_vs_simulated = compare_executed_vs_simulated
    end

    def analyze
      {
        executed_signals: analyze_executed,
        simulated_signals: analyze_simulated,
        not_executed_signals: analyze_not_executed,
        comparison: @compare_executed_vs_simulated ? compare_executed_vs_simulated : nil,
        summary: generate_summary,
      }
    end

    private

    def analyze_executed
      executed = @signals.executed
      total = executed.count
      return empty_analysis if total.zero?

      # For paper positions, get actual P&L
      paper_positions = executed.paper.joins(:paper_position).where.not(paper_positions: { status: "open" })
      live_orders = executed.live.joins(:order).where(orders: { status: "executed" })

      # Calculate actual P&L from positions
      paper_pnl = paper_positions.sum do |s|
        pos = s.paper_position
        pos.closed? ? (pos.realized_pnl || 0) : (pos.unrealized_pnl || 0)
      end
      paper_count = paper_positions.count

      {
        total: total,
        paper_count: executed.paper.count,
        live_count: executed.live.count,
        paper_closed_count: paper_count,
        paper_total_pnl: paper_pnl.round(2),
        paper_avg_pnl: paper_count.positive? ? (paper_pnl / paper_count).round(2) : 0,
        paper_win_rate: calculate_win_rate(paper_positions),
        live_count: live_orders.count,
      }
    end

    def analyze_simulated
      simulated = @signals.simulated
      total = simulated.count
      return empty_analysis if total.zero?

      profitable = simulated.where("simulated_pnl > 0").count
      loss_making = simulated.where("simulated_pnl < 0").count
      breakeven = simulated.where("simulated_pnl = 0").count

      total_pnl = simulated.sum(:simulated_pnl) || 0
      avg_pnl = total.positive? ? (total_pnl / total).round(2) : 0

      {
        total: total,
        profitable_count: profitable,
        loss_making_count: loss_making,
        breakeven_count: breakeven,
        win_rate: total.positive? ? ((profitable.to_f / total) * 100).round(2) : 0,
        total_pnl: total_pnl.round(2),
        avg_pnl: avg_pnl,
        total_pnl_pct: calculate_avg_pnl_pct(simulated),
        sl_hit_count: simulated.where(simulated_exit_reason: "sl_hit").count,
        tp_hit_count: simulated.where(simulated_exit_reason: "tp_hit").count,
        time_based_exit_count: simulated.where(simulated_exit_reason: "time_based").count,
        avg_holding_days: simulated.average(:simulated_holding_days)&.round(1) || 0,
      }
    end

    def analyze_not_executed
      not_executed = @signals.not_executed
      total = not_executed.count
      return empty_analysis if total.zero?

      insufficient_balance = not_executed.where("execution_reason LIKE ?", "%Insufficient%").count
      risk_limits = not_executed.where("execution_reason LIKE ?", "%risk%").count
      pending_approval = not_executed.pending_approval.count

      {
        total: total,
        insufficient_balance_count: insufficient_balance,
        risk_limit_exceeded_count: risk_limits,
        pending_approval_count: pending_approval,
        simulated_count: not_executed.simulated.count,
        not_simulated_count: not_executed.not_simulated.count,
      }
    end

    def compare_executed_vs_simulated
      executed_paper = @signals.executed.paper.joins(:paper_position).where.not(paper_positions: { status: "open" })
      simulated_not_executed = @signals.not_executed.simulated

      return { message: "Insufficient data for comparison" } if executed_paper.empty? && simulated_not_executed.empty?

      executed_pnl = executed_paper.sum do |s|
        pos = s.paper_position
        pos.closed? ? (pos.realized_pnl || 0) : (pos.unrealized_pnl || 0)
      end
      simulated_pnl = simulated_not_executed.sum(:simulated_pnl) || 0

      {
        executed_count: executed_paper.count,
        executed_total_pnl: executed_pnl.round(2),
        executed_avg_pnl: executed_paper.count.positive? ? (executed_pnl / executed_paper.count).round(2) : 0,
        simulated_count: simulated_not_executed.count,
        simulated_total_pnl: simulated_pnl.round(2),
        simulated_avg_pnl: simulated_not_executed.count.positive? ? (simulated_pnl / simulated_not_executed.count).round(2) : 0,
        opportunity_cost: (simulated_pnl - executed_pnl).round(2),
        opportunity_cost_pct: executed_pnl.zero? ? 0 : ((simulated_pnl - executed_pnl) / executed_pnl.abs * 100).round(2),
      }
    end

    def calculate_win_rate(positions)
      return 0 if positions.empty?

      winners = positions.count do |s|
        pos = s.paper_position
        pnl = pos.closed? ? (pos.realized_pnl || 0) : (pos.unrealized_pnl || 0)
        pnl.positive?
      end
      (winners.to_f / positions.count * 100).round(2)
    end

    def calculate_avg_pnl_pct(signals)
      return 0 if signals.empty?

      total_pct = signals.sum(:simulated_pnl_pct) || 0
      (total_pct / signals.count).round(2)
    end

    def generate_summary
      total_signals = @signals.count
      executed_count = @signals.executed.count
      simulated_count = @signals.simulated.count
      not_executed_count = @signals.not_executed.count

      {
        total_signals: total_signals,
        executed_count: executed_count,
        executed_pct: total_signals.positive? ? ((executed_count.to_f / total_signals) * 100).round(2) : 0,
        not_executed_count: not_executed_count,
        not_executed_pct: total_signals.positive? ? ((not_executed_count.to_f / total_signals) * 100).round(2) : 0,
        simulated_count: simulated_count,
        simulated_pct: not_executed_count.positive? ? ((simulated_count.to_f / not_executed_count) * 100).round(2) : 0,
      }
    end

    def empty_analysis
      {
        total: 0,
        message: "No data available",
      }
    end
  end
end
