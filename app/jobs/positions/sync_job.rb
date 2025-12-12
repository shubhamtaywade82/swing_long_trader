# frozen_string_literal: true

module Positions
  # Job to sync positions with DhanHQ and reconcile prices
  class SyncJob < ApplicationJob
    include JobLogging

    queue_as :default

    def perform(sync_type: "all")
      case sync_type
      when "live"
        reconcile_live
      when "paper"
        reconcile_paper
      else
        reconcile_all
      end
    end

    private

    def reconcile_all
      live_result = Positions::Reconciler.reconcile_live
      paper_result = Positions::Reconciler.reconcile_paper

      Rails.logger.info(
        "[Positions::SyncJob] Reconciliation complete: " \
        "live_positions=#{live_result[:positions_updated]}, " \
        "paper_positions=#{paper_result[:positions_updated]}",
      )

      {
        live: live_result,
        paper: paper_result,
      }
    rescue StandardError => e
      Rails.logger.error("[Positions::SyncJob] Reconciliation failed: #{e.message}")
      Telegram::Notifier.send_error_alert("Position sync failed: #{e.message}", context: "PositionSyncJob")
      raise
    end

    def reconcile_live
      result = Positions::Reconciler.reconcile_live

      if result[:success]
        Rails.logger.info(
          "[Positions::SyncJob] Live positions synced: #{result[:positions_updated]} positions updated",
        )
      else
        Rails.logger.error("[Positions::SyncJob] Live sync failed: #{result[:error]}")
      end

      result
    end

    def reconcile_paper
      result = Positions::Reconciler.reconcile_paper

      if result[:success]
        Rails.logger.info(
          "[Positions::SyncJob] Paper positions reconciled: #{result[:positions_updated]} positions updated",
        )
      else
        Rails.logger.error("[Positions::SyncJob] Paper reconciliation failed: #{result[:error]}")
      end

      result
    end
  end
end
