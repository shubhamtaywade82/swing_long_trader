# frozen_string_literal: true

module Dashboard
  class Broadcaster < ApplicationService
    def self.broadcast_stats
      new.broadcast_stats
    end

    def broadcast_stats
      stats = calculate_stats

      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "stats_update",
          stats: stats,
        },
      )
    end

    private

    def calculate_stats
      {
        livePositions: Position.live.open.count,
        paperPositions: Position.paper.open.count,
        unrealizedPnl: format_currency(
          Position.live.open.sum(:unrealized_pnl) + Position.paper.open.sum(:unrealized_pnl),
        ),
        pendingOrders: Order.pending_approval.count,
      }
    end

    def format_currency(amount)
      "₹#{amount.to_i.abs}"
    end
  end
end
