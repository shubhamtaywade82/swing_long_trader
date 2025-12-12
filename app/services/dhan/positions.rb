# frozen_string_literal: true

module Dhan
  # Service to sync positions from DhanHQ API
  class Positions < ApplicationService
    def self.sync_all
      new.sync_all
    end

    def self.sync_position(dhan_position_id)
      new.sync_position(dhan_position_id)
    end

    def sync_all
      client = get_dhan_client
      return { success: false, error: "DhanHQ client not available" } unless client

      begin
        # Get positions from DhanHQ API
        # Note: Adjust method name based on actual DhanHQ API
        response = client.get_positions || client.get_holdings || client.get_portfolio

        unless response && response.is_a?(Array)
          Rails.logger.warn("[Dhan::Positions] Invalid response format from DhanHQ API")
          return { success: false, error: "Invalid API response format" }
        end

        synced_count = 0
        created_count = 0
        updated_count = 0

        response.each do |dhan_position|
          result = sync_single_position(dhan_position)
          synced_count += 1 if result[:success]
          created_count += 1 if result[:created]
          updated_count += 1 if result[:updated]
        end

        # Mark positions as not synced if they're not in DhanHQ response
        mark_missing_positions_as_closed(response.map { |p| p["positionId"] || p["securityId"] })

        {
          success: true,
          synced_count: synced_count,
          created_count: created_count,
          updated_count: updated_count,
        }
      rescue StandardError => e
        Rails.logger.error("[Dhan::Positions] Sync failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def sync_position(dhan_position_id)
      client = get_dhan_client
      return { success: false, error: "DhanHQ client not available" } unless client

      begin
        # Get single position from DhanHQ API
        response = client.get_position(dhan_position_id) || client.get_holding(dhan_position_id)

        unless response
          return { success: false, error: "Position not found in DhanHQ" }
        end

        sync_single_position(response)
      rescue StandardError => e
        Rails.logger.error("[Dhan::Positions] Sync failed for position #{dhan_position_id}: #{e.message}")
        { success: false, error: e.message }
      end
    end

    private

    def sync_single_position(dhan_position)
      # Extract position data from DhanHQ response
      # Adjust field names based on actual DhanHQ API response format
      dhan_position_id = dhan_position["positionId"] || dhan_position["securityId"] || dhan_position["id"]
      security_id = dhan_position["securityId"] || dhan_position["security_id"]
      symbol = dhan_position["symbol"] || dhan_position["symbolName"] || dhan_position["symbol_name"]
      quantity = dhan_position["quantity"] || dhan_position["qty"] || 0
      average_price = dhan_position["averagePrice"] || dhan_position["average_price"] || dhan_position["price"]
      current_price = dhan_position["currentPrice"] || dhan_position["ltp"] || dhan_position["lastPrice"] || average_price
      direction = determine_direction(dhan_position)

      return { success: false, error: "Missing required fields" } unless security_id && symbol

      # Find instrument
      instrument = Instrument.find_by(security_id: security_id)
      unless instrument
        Rails.logger.warn("[Dhan::Positions] Instrument not found for security_id: #{security_id}")
        return { success: false, error: "Instrument not found" }
      end

      # Find or create position
      position = Position.find_or_initialize_by(dhan_position_id: dhan_position_id)

      is_new = position.new_record?

      # Find associated order if exists
      order = Order.find_by(dhan_order_id: dhan_position["orderId"]) if dhan_position["orderId"]

      # Update position
      position.assign_attributes(
        instrument: instrument,
        order: order,
        symbol: symbol,
        direction: direction,
        entry_price: average_price || current_price,
        current_price: current_price,
        quantity: quantity,
        average_entry_price: average_price,
        filled_quantity: quantity,
        dhan_position_id: dhan_position_id,
        dhan_position_data: dhan_position.to_json,
        synced_with_dhan: true,
        last_synced_at: Time.current,
        status: quantity.positive? ? "open" : "closed",
      )

      # Set opened_at if new
      position.opened_at ||= Time.current

      # Update unrealized P&L
      position.update_unrealized_pnl! if position.open?

      # Update sync metadata
      sync_meta = position.sync_metadata_hash
      sync_meta[:sync_history] ||= []
      sync_meta[:sync_history] << {
        synced_at: Time.current,
        dhan_data: dhan_position,
        changes: position.changed_attributes,
      }
      position.sync_metadata = sync_meta.to_json

      if position.save
        {
          success: true,
          created: is_new,
          updated: !is_new,
          position: position,
        }
      else
        {
          success: false,
          error: position.errors.full_messages.join(", "),
        }
      end
    rescue StandardError => e
      Rails.logger.error("[Dhan::Positions] Failed to sync position: #{e.message}")
      { success: false, error: e.message }
    end

    def determine_direction(dhan_position)
      # Determine direction from DhanHQ data
      # Adjust based on actual API response format
      buy_qty = dhan_position["buyQuantity"] || dhan_position["buy_quantity"] || 0
      sell_qty = dhan_position["sellQuantity"] || dhan_position["sell_quantity"] || 0
      net_qty = dhan_position["netQuantity"] || dhan_position["net_quantity"] || (buy_qty - sell_qty)

      if net_qty.positive?
        "long"
      elsif net_qty.negative?
        "short"
      else
        # Default to long if can't determine
        "long"
      end
    end

    def mark_missing_positions_as_closed(dhan_position_ids)
      # Find positions that are open in our DB but not in DhanHQ response
      open_positions = Position.open.where(synced_with_dhan: true)
      missing_positions = open_positions.where.not(dhan_position_id: dhan_position_ids)

      missing_positions.find_each do |position|
        # Check if position was closed (quantity = 0)
        # If DhanHQ doesn't return it, it might be closed
        # Update from latest order status instead
        if position.order&.executed? && position.order.filled_quantity.zero?
          position.mark_as_closed!(
            exit_price: position.current_price,
            exit_reason: "synced_closed",
          )
        end
      end
    end

    def get_dhan_client
      require "dhan_hq"
      DhanHQ::Client.new(api_type: :order_api)
    rescue LoadError
      Rails.logger.warn("[Dhan::Positions] DhanHQ gem not installed")
      nil
    rescue StandardError => e
      Rails.logger.error("[Dhan::Positions] Failed to create DhanHQ client: #{e.message}")
      nil
    end
  end
end
