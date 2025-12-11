# frozen_string_literal: true

module Dhan
  # Wrapper for DhanHQ order placement API
  # Provides a clean interface for placing orders with error handling
  class Orders < ApplicationService
    def self.place_order(instrument:, order_type:, transaction_type:, quantity:, price: nil, trigger_price: nil, client_order_id: nil, dry_run: false)
      new(
        instrument: instrument,
        order_type: order_type,
        transaction_type: transaction_type,
        quantity: quantity,
        price: price,
        trigger_price: trigger_price,
        client_order_id: client_order_id,
        dry_run: dry_run
      ).place_order
    end

    def initialize(instrument:, order_type:, transaction_type:, quantity:, price: nil, trigger_price: nil, client_order_id: nil, dry_run: false)
      @instrument = instrument
      @order_type = order_type.to_s.upcase
      @transaction_type = transaction_type.to_s.upcase
      @quantity = quantity.to_i
      @price = price&.to_f
      @trigger_price = trigger_price&.to_f
      @client_order_id = client_order_id || generate_client_order_id
      @dry_run = dry_run || (ENV['DRY_RUN'] == 'true')
    end

    def place_order
      # Validate inputs
      validation = validate_order
      return validation unless validation[:success]

      # Check for duplicate order (idempotency)
      existing_order = check_duplicate_order
      return { success: true, order: existing_order, duplicate: true } if existing_order

      # Create order record
      order = create_order_record

      # Place order (or simulate in dry-run mode)
      if @dry_run
        simulate_order_placement(order)
      else
        execute_order_placement(order)
      end
    rescue StandardError => e
      handle_order_error(order, e)
    end

    private

    def validate_order
      return { success: false, error: 'Invalid instrument' } unless @instrument.present?
      return { success: false, error: 'Invalid quantity' } if @quantity <= 0
      return { success: false, error: 'Price required for LIMIT orders' } if @order_type == 'LIMIT' && @price.nil?
      return { success: false, error: 'Trigger price required for SL orders' } if %w[SL SL-M].include?(@order_type) && @trigger_price.nil?
      return { success: false, error: 'Invalid transaction type' } unless %w[BUY SELL].include?(@transaction_type)
      return { success: false, error: 'Invalid order type' } unless %w[MARKET LIMIT SL SL-M].include?(@order_type)

      { success: true }
    end

    def check_duplicate_order
      Order.find_by(client_order_id: @client_order_id)
    end

    def create_order_record
      Order.create!(
        instrument: @instrument,
        client_order_id: @client_order_id,
        symbol: @instrument.symbol_name,
        exchange_segment: @instrument.exchange_segment,
        security_id: @instrument.security_id,
        product_type: 'EQUITY', # Default for swing trading
        order_type: @order_type,
        transaction_type: @transaction_type,
        quantity: @quantity,
        price: @price,
        trigger_price: @trigger_price,
        validity: 'DAY',
        status: 'pending',
        dry_run: @dry_run,
        metadata: {
          placed_at: Time.current,
          dry_run: @dry_run
        }.to_json
      )
    end

    def execute_order_placement(order)
      # Get DhanHQ client
      client = get_dhan_client
      return { success: false, error: 'DhanHQ client not available', order: order } unless client

      # Build order payload
      payload = build_order_payload

      # Place order via DhanHQ API
      response = client.place_order(payload)

      # Update order record with response
      update_order_from_response(order, response)

      if response['status'] == 'success'
        { success: true, order: order, dhan_response: response }
      else
        error_msg = response['message'] || 'Order placement failed'
        order.update(status: 'rejected', error_message: error_msg, dhan_response: response.to_json)
        { success: false, error: error_msg, order: order }
      end
    rescue StandardError => e
      handle_order_error(order, e)
    end

    def simulate_order_placement(order)
      # Simulate successful order placement in dry-run mode
      simulated_response = {
        'status' => 'success',
        'orderId' => "DRY_RUN_#{order.id}",
        'message' => 'Order placed (DRY RUN)'
      }

      order.update!(
        status: 'placed',
        dhan_order_id: "DRY_RUN_#{order.id}",
        dhan_response: simulated_response.to_json,
        metadata: order.metadata_hash.merge(simulated: true, simulated_at: Time.current).to_json
      )

      Rails.logger.info("[Dhan::Orders] DRY RUN: Order #{order.client_order_id} simulated successfully")

      { success: true, order: order, dhan_response: simulated_response, dry_run: true }
    end

    def build_order_payload
      payload = {
        securityId: @instrument.security_id,
        exchangeSegment: @instrument.exchange_segment,
        productType: 'EQUITY',
        orderType: @order_type,
        transactionType: @transaction_type,
        quantity: @quantity,
        validity: 'DAY',
        clientId: @client_order_id
      }

      payload[:price] = @price if @price
      payload[:triggerPrice] = @trigger_price if @trigger_price
      payload[:disclosedQuantity] = 0

      payload
    end

    def update_order_from_response(order, response)
      if response['status'] == 'success'
        order.update!(
          status: 'placed',
          dhan_order_id: response['orderId'],
          exchange_order_id: response['exchangeOrderId'],
          dhan_response: response.to_json
        )
      else
        order.update!(
          status: 'rejected',
          error_message: response['message'] || 'Order rejected',
          dhan_response: response.to_json
        )
      end
    end

    def handle_order_error(order, error)
      error_msg = error.message
      Rails.logger.error("[Dhan::Orders] Order placement failed: #{error_msg}")

      if order
        order.update!(
          status: 'failed',
          error_message: error_msg,
          dhan_response: { error: error_msg, backtrace: error.backtrace.first(5) }.to_json
        )
      end

      { success: false, error: error_msg, order: order }
    end

    def get_dhan_client
      begin
        require 'dhan_hq'
        DhanHQ::Client.new(api_type: :order_api)
      rescue LoadError
        Rails.logger.warn('[Dhan::Orders] DhanHQ gem not installed')
        nil
      rescue StandardError => e
        Rails.logger.error("[Dhan::Orders] Failed to create DhanHQ client: #{e.message}")
        nil
      end
    end

    def generate_client_order_id
      timestamp = Time.current.to_i.to_s[-6..]
      "#{@transaction_type[0]}-#{@instrument.security_id}-#{timestamp}"
    end
  end
end

