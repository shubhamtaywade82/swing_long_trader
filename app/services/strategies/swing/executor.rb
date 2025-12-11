# frozen_string_literal: true

module Strategies
  module Swing
    # Executes swing trading signals by placing orders
    # Includes risk management, idempotency, and safeguards
    class Executor < ApplicationService
      def self.call(signal, dry_run: nil)
        new(signal: signal, dry_run: dry_run).call
      end

      def initialize(signal:, dry_run: nil)
        @signal = signal
        @instrument = Instrument.find_by(id: signal[:instrument_id])
        @dry_run = dry_run.nil? ? (ENV['DRY_RUN'] == 'true') : dry_run
        @risk_config = AlgoConfig.fetch(:risk) || {}
      end

      def call
        # Validate signal
        validation = validate_signal
        return validation unless validation[:success]

        # Check risk limits
        risk_check = check_risk_limits
        return risk_check unless risk_check[:success]

        # Check circuit breaker
        circuit_check = check_circuit_breaker
        return circuit_check unless circuit_check[:success]

        # Check if manual approval required (first 30 trades)
        approval_check = check_manual_approval_required
        return approval_check unless approval_check[:success]

        # Place order
        place_entry_order
      end

      private

      def validate_signal
        return { success: false, error: 'Invalid signal' } unless @signal.present?
        return { success: false, error: 'Instrument not found' } unless @instrument.present?
        return { success: false, error: 'Missing entry price' } unless @signal[:entry_price]
        return { success: false, error: 'Missing quantity' } unless @signal[:qty]
        return { success: false, error: 'Missing direction' } unless @signal[:direction]

        { success: true }
      end

      def check_risk_limits
        # Check max position size per instrument
        instrument_exposure = calculate_instrument_exposure
        max_per_instrument = @risk_config[:max_position_size_pct] || 10.0
        max_value = (get_current_capital * max_per_instrument / 100.0)
        order_value = @signal[:entry_price] * @signal[:qty]

        if order_value > max_value
          return {
            success: false,
            error: "Order exceeds max position size: ₹#{order_value.round(2)} > ₹#{max_value.round(2)} (#{max_per_instrument}%)"
          }
        end

        # Check max total exposure
        total_exposure = calculate_total_exposure + order_value
        max_total = @risk_config[:max_total_exposure_pct] || 50.0
        max_total_value = (get_current_capital * max_total / 100.0)

        if total_exposure > max_total_value
          return {
            success: false,
            error: "Total exposure exceeds limit: ₹#{total_exposure.round(2)} > ₹#{max_total_value.round(2)} (#{max_total}%)"
          }
        end

        { success: true }
      end

      def check_circuit_breaker
        # Check recent order failure rate
        recent_orders = Order.where('created_at > ?', 1.hour.ago)
        total_recent = recent_orders.count
        failed_recent = recent_orders.failed.count

        return { success: true } if total_recent.zero?

        failure_rate = (failed_recent.to_f / total_recent * 100)
        max_failure_rate = 50.0 # 50% failure rate triggers circuit breaker

        if failure_rate > max_failure_rate
          return {
            success: false,
            error: "Circuit breaker activated: #{failure_rate.round(1)}% failure rate in last hour"
          }
        end

        { success: true }
      end

      def check_manual_approval_required
        # Skip approval check in dry-run mode
        return { success: true } if @dry_run

        # Get configuration
        execution_config = AlgoConfig.fetch(:execution) || {}
        manual_approval_enabled = execution_config[:manual_approval]&.dig(:enabled) != false
        manual_approval_count = execution_config[:manual_approval]&.dig(:count) || 30

        # If manual approval is disabled, skip
        return { success: true } unless manual_approval_enabled

        # Count executed trades (excluding dry-run)
        executed_count = Order.real.where(status: 'executed').count

        # If we've already executed 30+ trades, no approval needed
        return { success: true } if executed_count >= manual_approval_count

        # For first 30 trades, require approval
        # Create order record with requires_approval flag
        # The order will be placed only after approval
        {
          success: false,
          requires_approval: true,
          executed_count: executed_count,
          remaining: manual_approval_count - executed_count,
          error: "Manual approval required for first #{manual_approval_count} trades (#{executed_count}/#{manual_approval_count} executed)"
        }
      end

      def place_entry_order
        # Check if paper trading is enabled
        if Rails.configuration.x.paper_trading.enabled
          return execute_paper_trade
        end

        # Determine order type (MARKET for swing trading)
        order_type = 'MARKET' # Swing trading typically uses market orders

        # Map direction to transaction type
        transaction_type = @signal[:direction] == :long ? 'BUY' : 'SELL'

        # Check if manual approval is required
        execution_config = AlgoConfig.fetch(:execution) || {}
        manual_approval_enabled = execution_config[:manual_approval]&.dig(:enabled) != false
        manual_approval_count = execution_config[:manual_approval]&.dig(:count) || 30
        executed_count = Order.real.where(status: 'executed').count
        requires_approval = manual_approval_enabled && !@dry_run && executed_count < manual_approval_count

        # Check if large order (requires confirmation)
        order_value = @signal[:entry_price] * @signal[:qty]
        large_order_threshold = get_current_capital * 0.05 # 5% of capital

        if order_value > large_order_threshold && !@dry_run
          # Send Telegram confirmation request
          send_large_order_confirmation(order_value)
        end

        # If approval required, create order with requires_approval flag
        if requires_approval
          return create_pending_approval_order(order_type, transaction_type, order_value)
        end

        # Place order via DhanHQ wrapper
        result = Dhan::Orders.place_order(
          instrument: @instrument,
          order_type: order_type,
          transaction_type: transaction_type,
          quantity: @signal[:qty],
          price: nil, # Market order
          client_order_id: generate_order_id,
          dry_run: @dry_run
        )

        # Log order placement
        log_order_placement(result)

        # Send Telegram notification
        send_order_notification(result) unless @dry_run

        result
      end

      def execute_paper_trade
        log_info("Executing paper trade (paper trading mode enabled)")
        result = PaperTrading::Executor.execute(@signal)

        if result[:success]
          {
            success: true,
            order: result[:position],
            paper_trade: true,
            message: result[:message]
          }
        else
          {
            success: false,
            error: result[:error],
            paper_trade: true
          }
        end
      rescue StandardError => e
        log_error("Paper trade execution failed: #{e.message}")
        {
          success: false,
          error: "Paper trade failed: #{e.message}",
          paper_trade: true
        }
      end

      def create_pending_approval_order(order_type, transaction_type, order_value)
        # Create order record with requires_approval flag
        order = Order.create!(
          instrument: @instrument,
          client_order_id: generate_order_id,
          symbol: @instrument.symbol_name,
          exchange_segment: @instrument.exchange_segment,
          security_id: @instrument.security_id,
          product_type: 'EQUITY',
          order_type: order_type,
          transaction_type: transaction_type,
          quantity: @signal[:qty],
          price: @signal[:entry_price],
          validity: 'DAY',
          status: 'pending',
          dry_run: false,
          requires_approval: true,
          metadata: {
            signal: @signal,
            order_value: order_value,
            created_at: Time.current,
            requires_approval: true
          }.to_json
        )

        # Send approval request notification
        send_approval_request(order, order_value)

        {
          success: false,
          requires_approval: true,
          order: order,
          message: "Order created, awaiting manual approval (#{Order.real.where(status: 'executed').count}/30 executed)"
        }
      rescue StandardError => e
        Rails.logger.error("[Strategies::Swing::Executor] Failed to create pending approval order: #{e.message}")
        { success: false, error: "Failed to create approval order: #{e.message}" }
      end

      def send_approval_request(order, order_value)
        executed_count = Order.real.where(status: 'executed').count
        remaining = 30 - executed_count

        message = "🔔 <b>Order Approval Required</b>\n\n"
        message += "Symbol: #{order.symbol}\n"
        message += "Type: #{order.transaction_type} #{order.order_type}\n"
        message += "Quantity: #{order.quantity}\n"
        message += "Price: ₹#{order.price}\n"
        message += "Order Value: ₹#{order_value.round(2)}\n"
        message += "Direction: #{@signal[:direction].to_s.upcase}\n"
        message += "\n📊 Progress: #{executed_count}/30 trades executed (#{remaining} remaining)\n"
        message += "\nOrder ID: #{order.client_order_id}\n"
        message += "\n⚠️ This order requires manual approval before execution."
        message += "\n\nApprove: rails orders:approve[#{order.id}]"
        message += "\nReject: rails orders:reject[#{order.id},reason]"

        Telegram::Notifier.send_error_alert(message, context: 'Order Approval Required')
      rescue StandardError => e
        Rails.logger.error("[Strategies::Swing::Executor] Failed to send approval request: #{e.message}")
      end

      def calculate_instrument_exposure
        # Calculate current exposure for this instrument
        active_orders = Order.where(instrument: @instrument, status: %w[pending placed]).sum do |order|
          (order.price || 0) * order.quantity
        end
        active_orders
      end

      def calculate_total_exposure
        # Calculate total exposure across all instruments
        Order.where(status: %w[pending placed]).sum do |order|
          (order.price || 0) * order.quantity
        end
      end

      def get_current_capital
        # Get current capital (from settings or default)
        Setting.fetch_i('portfolio.current_capital', 100_000)
      end

      def generate_order_id
        timestamp = Time.current.to_i.to_s[-6..]
        "#{@signal[:direction].to_s.upcase[0]}-#{@instrument.security_id}-#{timestamp}"
      end

      def send_large_order_confirmation(order_value)
        message = "⚠️ <b>Large Order Alert</b>\n\n"
        message += "Order Value: ₹#{order_value.round(2)}\n"
        message += "Symbol: #{@instrument.symbol_name}\n"
        message += "Direction: #{@signal[:direction].to_s.upcase}\n"
        message += "Quantity: #{@signal[:qty]}\n"
        message += "\nThis order exceeds 5% of capital. Please review."

        Telegram::Notifier.send_error_alert(message, context: 'Large Order')
      rescue StandardError => e
        Rails.logger.error("[Strategies::Swing::Executor] Failed to send large order alert: #{e.message}")
      end

      def send_order_notification(result)
        return unless result[:success] && result[:order]

        order = result[:order]
        message = "📊 <b>Order Placed</b>\n\n"
        message += "Symbol: #{order.symbol}\n"
        message += "Type: #{order.transaction_type} #{order.order_type}\n"
        message += "Quantity: #{order.quantity}\n"
        message += "Price: #{order.price ? "₹#{order.price}" : 'Market'}\n"
        message += "Status: #{order.status}\n"
        message += "Order ID: #{order.client_order_id}"

        Telegram::Notifier.send_error_alert(message, context: 'Order Placement')
      rescue StandardError => e
        Rails.logger.error("[Strategies::Swing::Executor] Failed to send order notification: #{e.message}")
      end

      def log_order_placement(result)
        if result[:success]
          Rails.logger.info(
            "[Strategies::Swing::Executor] Order placed: " \
            "#{result[:order]&.symbol} #{result[:order]&.transaction_type} " \
            "#{result[:order]&.quantity} @ #{result[:order]&.price || 'Market'} " \
            "(#{@dry_run ? 'DRY RUN' : 'LIVE'})"
          )
        else
          Rails.logger.error(
            "[Strategies::Swing::Executor] Order failed: #{result[:error]} " \
            "(#{@dry_run ? 'DRY RUN' : 'LIVE'})"
          )
        end
      end
    end
  end
end

