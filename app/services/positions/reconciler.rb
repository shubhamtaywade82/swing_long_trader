# frozen_string_literal: true

module Positions
  # Reconciles positions for both live and paper trading
  # Updates prices, calculates P&L, checks exit conditions
  class Reconciler < ApplicationService
    def self.reconcile_all
      new.reconcile_all
    end

    def self.reconcile_live
      new.reconcile_live
    end

    def self.reconcile_paper
      new.reconcile_paper
    end

    def reconcile_all
      {
        live: reconcile_live,
        paper: reconcile_paper,
      }
    end

    def reconcile_live
      # Sync with DhanHQ first
      sync_result = Dhan::Positions.sync_all

      # Update all open positions
      open_positions = Position.open.includes(:instrument)
      updated_count = 0

      open_positions.find_each do |position|
        # Update current price from instrument LTP
        current_price = position.instrument.ltp
        next unless current_price

        position.update!(current_price: current_price)
        position.update_highest_lowest_price!
        position.update_unrealized_pnl!

        updated_count += 1
      end

      {
        success: true,
        synced_with_dhan: sync_result[:success],
        positions_updated: updated_count,
        sync_details: sync_result,
      }
    rescue StandardError => e
      Rails.logger.error("[Positions::Reconciler] Live reconciliation failed: #{e.message}")
      { success: false, error: e.message }
    end

    def reconcile_paper
      # Update all open paper positions
      portfolio = PaperTrading::Portfolio.find_or_create_default
      open_positions = portfolio.open_positions.includes(:instrument)
      updated_count = 0

      open_positions.find_each do |position|
        # Update current price from latest candle
        latest_candle = CandleSeriesRecord
                        .where(instrument_id: position.instrument_id, timeframe: "1D")
                        .order(timestamp: :desc)
                        .first

        next unless latest_candle

        position.update_current_price!(latest_candle.close)
        updated_count += 1
      end

      # Update portfolio equity
      portfolio.update_equity!
      portfolio.update_drawdown!

      {
        success: true,
        positions_updated: updated_count,
        portfolio_equity: portfolio.total_equity,
        available_capital: portfolio.available_capital,
      }
    rescue StandardError => e
      Rails.logger.error("[Positions::Reconciler] Paper reconciliation failed: #{e.message}")
      { success: false, error: e.message }
    end
  end
end
