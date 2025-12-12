# frozen_string_literal: true

module Metrics
  # Tracks P&L for executed orders
  # Calculates realized and unrealized P&L
  class PnlTracker
    def self.track_order_execution(order)
      new.track_order_execution(order)
    end

    def self.calculate_realized_pnl(order)
      return 0 unless order.executed?

      entry_value = (order.price || 0) * order.quantity
      exit_value = order.average_price * order.filled_quantity

      if order.buy?
        exit_value - entry_value
      else
        entry_value - exit_value
      end
    end

    def self.calculate_unrealized_pnl(order, current_price)
      return 0 unless order.placed? && current_price

      entry_value = (order.price || 0) * order.quantity
      current_value = current_price * order.quantity

      if order.buy?
        current_value - entry_value
      else
        entry_value - current_value
      end
    end

    def self.get_daily_pnl(date = Time.zone.today)
      # Use date range to handle timezone-aware timestamps correctly
      orders = Order.where(created_at: date.all_day)
      calculate_total_pnl(orders)
    end

    def self.get_weekly_pnl(week_start = Time.zone.today.beginning_of_week)
      week_end = week_start.end_of_week
      orders = Order.where(created_at: week_start..week_end)
      calculate_total_pnl(orders)
    end

    def self.get_monthly_pnl(month_start = Time.zone.today.beginning_of_month)
      month_end = month_start.end_of_month
      orders = Order.where(created_at: month_start..month_end)
      calculate_total_pnl(orders)
    end

    def self.get_total_pnl
      orders = Order.executed
      calculate_total_pnl(orders)
    end

    def track_order_execution(order)
      return unless order.executed?

      pnl = self.class.calculate_realized_pnl(order)
      pnl_pct = calculate_pnl_percentage(order, pnl)

      # Store P&L in order metadata
      metadata = order.metadata_hash
      metadata["pnl"] = pnl
      metadata["pnl_pct"] = pnl_pct
      metadata["executed_at"] = Time.current
      order.update!(metadata: metadata.to_json)

      # Track in daily metrics
      track_daily_pnl(order.created_at.to_date, pnl)

      Rails.logger.info(
        "[Metrics::PnlTracker] Tracked P&L: " \
        "order_id=#{order.id}, " \
        "symbol=#{order.symbol}, " \
        "pnl=₹#{pnl.round(2)}, " \
        "pnl_pct=#{pnl_pct.round(2)}%",
      )

      { pnl: pnl, pnl_pct: pnl_pct }
    end

    private

    def calculate_pnl_percentage(order, pnl)
      entry_value = (order.price || 0) * order.quantity
      return 0 if entry_value.zero?

      (pnl / entry_value * 100).round(4)
    end

    def track_daily_pnl(date, pnl)
      key = "pnl.daily.#{date.strftime('%Y-%m-%d')}"
      current = Setting.fetch_f(key, 0.0)
      Setting.put(key, current + pnl)
    end

    def self.calculate_total_pnl(orders)
      total = 0.0
      orders.executed.find_each do |order|
        pnl = order.metadata_hash["pnl"] || calculate_realized_pnl(order)
        total += pnl.to_f
      end
      total
    end
  end
end
