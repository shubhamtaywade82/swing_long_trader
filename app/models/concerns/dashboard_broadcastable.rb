# frozen_string_literal: true

module DashboardBroadcastable
  extend ActiveSupport::Concern

  included do
    after_update :broadcast_dashboard_update, if: :should_broadcast?
  end

  private

  def should_broadcast?
    # Only broadcast if relevant attributes changed
    if is_a?(Position)
      saved_change_to_current_price? || saved_change_to_unrealized_pnl? || saved_change_to_status?
    elsif is_a?(TradingSignal)
      saved_change_to_executed? || saved_change_to_execution_status?
    elsif is_a?(Order)
      saved_change_to_status?
    else
      false
    end
  end

  def broadcast_dashboard_update
    if is_a?(Position)
      broadcast_position_update
    elsif is_a?(TradingSignal)
      broadcast_signal_update
    elsif is_a?(Order)
      broadcast_order_update
    end
  end

  def broadcast_position_update
    ActionCable.server.broadcast(
      "dashboard_updates",
      {
        type: "position_update",
        position: {
          id: id,
          symbol: symbol,
          current_price: current_price,
          unrealized_pnl: unrealized_pnl,
          status: status,
        },
      },
    )
  end

  def broadcast_signal_update
    ActionCable.server.broadcast(
      "dashboard_updates",
      {
        type: "signal_update",
        signal: {
          id: id,
          symbol: symbol,
          executed: executed,
          execution_status: execution_status,
        },
      },
    )
  end

  def broadcast_order_update
    ActionCable.server.broadcast(
      "dashboard_updates",
      {
        type: "order_update",
        order: {
          id: id,
          symbol: symbol,
          status: status,
          transaction_type: transaction_type,
        },
      },
    )
  end
end
