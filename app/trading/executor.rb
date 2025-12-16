# frozen_string_literal: true

module Trading
  # Executor Gatekeeper - Final gate before order placement
  # Order placement allowed ONLY if:
  # 1. Decision Engine approved
  # 2. Kill-switch clear
  # 3. Mode allows execution
  # 4. FSM state valid
  class Executor < ApplicationService
    def self.execute(trade_recommendation:, decision_result:, portfolio: nil, mode: nil, dry_run: false)
      new(
        trade_recommendation: trade_recommendation,
        decision_result: decision_result,
        portfolio: portfolio,
        mode: mode || current_mode,
        dry_run: dry_run,
      ).execute
    end

    def initialize(trade_recommendation:, decision_result:, portfolio: nil, mode: nil, dry_run: false)
      @recommendation = trade_recommendation
      @decision_result = decision_result
      @portfolio = portfolio
      @mode = mode || Trading::Config.current_mode
      @dry_run = dry_run
    end

    def execute
      # Gate 1: Decision Engine must have approved
      unless @decision_result[:approved]
        return {
          success: false,
          error: "Decision Engine rejected: #{@decision_result[:reason]}",
          gate: "decision_engine",
          decision_result: @decision_result,
        }
      end

      # Gate 2: Check kill-switch
      kill_switch_check = check_kill_switch
      unless kill_switch_check[:clear]
        return {
          success: false,
          error: "Kill-switch active: #{kill_switch_check[:reason]}",
          gate: "kill_switch",
          kill_switch: kill_switch_check,
        }
      end

      # Gate 3: Mode must allow execution
      mode_check = check_mode_allows_execution
      unless mode_check[:allowed]
        return {
          success: false,
          error: "Mode does not allow execution: #{mode_check[:reason]}",
          gate: "mode",
          mode_check: mode_check,
        }
      end

      # Gate 4: FSM state must be valid for execution
      fsm_check = check_fsm_state
      unless fsm_check[:valid]
        return {
          success: false,
          error: "FSM state invalid for execution: #{fsm_check[:reason]}",
          gate: "fsm_state",
          fsm_check: fsm_check,
        }
      end

      # All gates passed - execute based on mode
      result = execute_by_mode

      # Log execution to audit log
      log_execution(result) if result

      result
    end

    private

    def check_kill_switch
      # Check manual kill-switch flag
      manual_kill = Rails.cache.read("trading_kill_switch:manual")
      if manual_kill == true
        return {
          clear: false,
          reason: "Manual kill-switch activated",
        }
      end

      # Check system context if available
      if @portfolio
        system_context = Trading::SystemContext.from_portfolio(@portfolio)
        
        # Check significant drawdown
        if system_context.significant_drawdown?(threshold: 15.0)
          return {
            clear: false,
            reason: "Significant drawdown: #{system_context.drawdown.round(2)}%",
          }
        end

        # Check consecutive losses
        if system_context.consecutive_losses >= 3
          return {
            clear: false,
            reason: "Too many consecutive losses: #{system_context.consecutive_losses}",
          }
        end

        # Check daily loss limit (if configured)
        config = Trading::Config.config_value("trading", "modes", "fully_automated", "kill_switches") || {}
        max_daily_loss_pct = config["max_daily_loss_pct"] || 5.0
        
        if system_context.today_pnl < 0
          total_capital = @portfolio.respond_to?(:total_equity) ? @portfolio.total_equity : 0
          if total_capital > 0
            daily_loss_pct = (system_context.today_pnl.abs / total_capital * 100.0).round(2)
            if daily_loss_pct >= max_daily_loss_pct
              return {
                clear: false,
                reason: "Daily loss limit exceeded: #{daily_loss_pct}% >= #{max_daily_loss_pct}%",
              }
            end
          end
        end
      end

      { clear: true }
    end

    def check_mode_allows_execution
      case @mode
      when "advisory"
        {
          allowed: false,
          reason: "Advisory mode - no execution allowed",
        }
      when "semi_automated"
        {
          allowed: true,
          reason: "Semi-automated mode - execution allowed with approval",
          requires_approval: true,
        }
      when "fully_automated"
        {
          allowed: true,
          reason: "Fully automated mode - execution allowed",
          requires_approval: false,
        }
      else
        {
          allowed: false,
          reason: "Unknown mode: #{@mode}",
        }
      end
    end

    def check_fsm_state
      lifecycle = @recommendation.lifecycle

      # Must be in APPROVED state to execute
      unless lifecycle.approved?
        return {
          valid: false,
          reason: "FSM state is #{lifecycle.current_state}, must be APPROVED",
        }
      end

      { valid: true }
    end

    def execute_by_mode
      mode_check = check_mode_allows_execution
      requires_approval = mode_check[:requires_approval] || false

      if @dry_run
        return execute_dry_run
      end

      case @mode
      when "semi_automated"
        execute_semi_automated(requires_approval: requires_approval)
      when "fully_automated"
        execute_fully_automated
      else
        {
          success: false,
          error: "Mode #{@mode} does not allow execution",
        }
      end
    end

    def execute_dry_run
      # Transition to QUEUED (simulated)
      @recommendation.lifecycle.queue!(reason: "Dry run - order would be queued")

      {
        success: true,
        dry_run: true,
        recommendation: @recommendation,
        message: "Dry run - order would be placed",
        lifecycle_state: @recommendation.lifecycle.current_state,
      }
    end

    def execute_semi_automated(requires_approval:)
      # Create order with requires_approval flag
      order = create_order(requires_approval: requires_approval)

      if requires_approval
        # Transition to QUEUED (waiting for approval)
        @recommendation.lifecycle.queue!(reason: "Order created, pending approval")

        {
          success: true,
          order: order,
          recommendation: @recommendation,
          message: "Order created, pending approval",
          lifecycle_state: @recommendation.lifecycle.current_state,
        }
      else
        # Auto-approve and execute
        approve_and_execute_order(order)
      end
    end

    def execute_fully_automated
      # Create order without approval requirement
      order = create_order(requires_approval: false)

      # Auto-approve and execute
      approve_and_execute_order(order)
    end

    def create_order(requires_approval:)
      # Determine if paper trading or live
      if Rails.configuration.x.paper_trading.enabled || @portfolio&.respond_to?(:paper?)
        create_paper_order(requires_approval: requires_approval)
      else
        create_live_order(requires_approval: requires_approval)
      end
    end

    def create_paper_order(requires_approval:)
      # Use existing PaperTrading::Executor
      signal = build_signal_hash

      result = PaperTrading::Executor.execute(signal, portfolio: @portfolio)

      if result[:success]
        # Transition to ENTERED
        @recommendation.lifecycle.enter!(reason: "Paper trade executed")

        {
          success: true,
          order: result[:position],
          recommendation: @recommendation,
          message: "Paper trade executed",
          lifecycle_state: @recommendation.lifecycle.current_state,
        }
      else
        # Transition to CANCELLED
        @recommendation.lifecycle.cancel!(reason: result[:error])

        {
          success: false,
          error: result[:error],
          recommendation: @recommendation,
          lifecycle_state: @recommendation.lifecycle.current_state,
        }
      end
    end

    def create_live_order(requires_approval:)
      # Create Order record
      instrument = Instrument.find_by(id: @recommendation.instrument_id)
      return { success: false, error: "Instrument not found" } unless instrument

      order = Order.create!(
        instrument: instrument,
        client_order_id: generate_order_id,
        symbol: @recommendation.symbol,
        exchange_segment: instrument.exchange_segment,
        security_id: instrument.security_id,
        product_type: "EQUITY",
        order_type: "LIMIT",
        transaction_type: @recommendation.long? ? "BUY" : "SELL",
        quantity: @recommendation.quantity,
        price: @recommendation.entry_price,
        stop_loss: @recommendation.stop_loss,
        target_price: @recommendation.target_prices.first&.first,
        validity: "DAY",
        status: "pending",
        requires_approval: requires_approval,
        metadata: {
          trade_recommendation: @recommendation.to_hash,
          decision_result: @decision_result,
          source: "trading_agent",
        }.to_json,
      )

      order
    end

    def approve_and_execute_order(order)
      # Approve order
      approval_result = Orders::Approval.approve(order.id, approved_by: "system")

      unless approval_result[:success]
        @recommendation.lifecycle.cancel!(reason: "Order approval failed: #{approval_result[:error]}")
        return {
          success: false,
          error: approval_result[:error],
          recommendation: @recommendation,
          lifecycle_state: @recommendation.lifecycle.current_state,
        }
      end

      # Transition to QUEUED (order approved, waiting for execution)
      @recommendation.lifecycle.queue!(reason: "Order approved")

      {
        success: true,
        order: order,
        recommendation: @recommendation,
        message: "Order approved and queued for execution",
        lifecycle_state: @recommendation.lifecycle.current_state,
      }
    end

    def build_signal_hash
      {
        instrument_id: @recommendation.instrument_id,
        symbol: @recommendation.symbol,
        direction: @recommendation.long? ? :long : :short,
        entry_price: @recommendation.entry_price,
        sl: @recommendation.stop_loss,
        tp: @recommendation.target_prices.first&.first,
        qty: @recommendation.quantity,
        confidence: @recommendation.confidence_score / 100.0,
        rr: @recommendation.risk_reward,
      }
    end

    def generate_order_id
      timestamp = Time.current.to_i.to_s[-6..]
      direction = @recommendation.long? ? "L" : "S"
      "#{direction}-#{@recommendation.instrument_id}-#{timestamp}"
    end

    def self.current_mode
      Trading::Config.current_mode
    end

    def log_execution(execution_result)
      return unless Trading::Config.dto_enabled?

      system_context = @portfolio ? Trading::SystemContext.from_portfolio(@portfolio) : Trading::SystemContext.empty

      audit_log = Trading::AuditLog.new(
        trade_recommendation: @recommendation,
        decision_result: @decision_result,
        system_context: system_context,
        llm_review: @decision_result[:llm_review],
      )

      audit_log.log_execution(execution_result)
    rescue StandardError => e
      Rails.logger.error("[Trading::Executor] Audit log failed: #{e.message}")
      # Don't fail execution if audit log fails
    end
  end
end
