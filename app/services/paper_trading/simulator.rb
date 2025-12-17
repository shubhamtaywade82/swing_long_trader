# frozen_string_literal: true

module PaperTrading
  # Simulates price updates and checks exit conditions
  class Simulator < ApplicationService
    def self.check_exits(portfolio: nil)
      portfolio ||= PaperTrading::Portfolio.find_or_create_default
      new(portfolio: portfolio).check_exits
    end

    def initialize(portfolio:)
      @portfolio = portfolio
    end

    def check_exits
      open_positions = @portfolio.open_positions.includes(:instrument)
      exited_count = 0

      open_positions.each do |position|
        # Update current price from latest candle
        update_position_price(position)

        # Update position in database (ensures sync)
        position.update_current_price!(position.current_price)

        # Check exit conditions
        exit_result = check_exit_conditions(position)
        next unless exit_result[:should_exit]

        # Execute exit
        exit_position(position, exit_result[:reason], exit_result[:exit_price])
        exited_count += 1
      end

      # Update portfolio after exits
      @portfolio.update_equity!
      @portfolio.update_drawdown!

      log_info("Checked #{open_positions.count} positions, exited #{exited_count}")
      { checked: open_positions.count, exited: exited_count }
    rescue StandardError => e
      log_error("Exit check failed: #{e.message}")
      raise
    end

    private

    def update_position_price(position)
      # Get latest price from candle series
      latest_candle = CandleSeriesRecord
                      .where(instrument_id: position.instrument_id, timeframe: :daily)
                      .order(timestamp: :desc)
                      .first

      return unless latest_candle

      current_price = latest_candle.close
      position.update_current_price!(current_price)
    end

    def check_exit_conditions(position)
      # Check SL hit
      if position.check_sl_hit?
        return {
          should_exit: true,
          reason: "sl_hit",
          exit_price: position.sl,
        }
      end

      # Check TP hit
      if position.check_tp_hit?
        return {
          should_exit: true,
          reason: "tp_hit",
          exit_price: position.tp,
        }
      end

      # Check time-based exit (max holding days)
      max_holding_days = AlgoConfig.fetch(%i[swing_trading strategy max_holding_days]) || 20
      if position.days_held >= max_holding_days
        return {
          should_exit: true,
          reason: "time_based",
          exit_price: position.current_price,
        }
      end

      { should_exit: false }
    end

    def exit_position(position, reason, exit_price)
      # Calculate P&L
      pnl = if position.long?
              (exit_price - position.entry_price) * position.quantity
            else
              (position.entry_price - exit_price) * position.quantity
            end

      pnl_pct = if position.long?
                  ((exit_price - position.entry_price) / position.entry_price * 100).round(2)
                else
                  ((position.entry_price - exit_price) / position.entry_price * 100).round(2)
                end

      # Update position
      position.update!(
        status: "closed",
        exit_price: exit_price,
        exit_reason: reason,
        closed_at: Time.current,
        pnl: pnl,
        pnl_pct: pnl_pct,
        holding_days: position.days_held,
      )

      # Update TradeOutcome if it exists
      update_trade_outcome_for_paper_position(position, exit_price: exit_price, exit_reason: reason)

      # Release reserved capital
      entry_value = position.entry_price * position.quantity
      @portfolio.decrement!(:reserved_capital, entry_value)

      # Update portfolio P&L and capital
      # Capital increases/decreases by the P&L amount
      @portfolio.increment!(:pnl_realized, pnl)
      if pnl.positive?
        @portfolio.increment!(:capital, pnl) # Add profit to capital
        PaperTrading::Ledger.credit(
          portfolio: @portfolio,
          amount: pnl,
          reason: "profit",
          description: "Profit from #{position.instrument.symbol_name}",
          position: position,
          meta: {
            symbol: position.instrument.symbol_name,
            entry_price: position.entry_price,
            exit_price: exit_price,
            pnl: pnl,
          },
        )
      else
        @portfolio.decrement!(:capital, pnl.abs) # Subtract loss from capital
        PaperTrading::Ledger.debit(
          portfolio: @portfolio,
          amount: pnl.abs,
          reason: "loss",
          description: "Loss from #{position.instrument.symbol_name}",
          position: position,
          meta: {
            symbol: position.instrument.symbol_name,
            entry_price: position.entry_price,
            exit_price: exit_price,
            pnl: pnl,
          },
        )
      end

      # Record exit in ledger (for audit trail)
      exit_value = exit_price * position.quantity
      PaperLedger.create!(
        paper_portfolio: @portfolio,
        paper_position: position,
        amount: exit_value,
        transaction_type: "credit",
        reason: "trade_exit",
        description: "Exit: #{position.instrument.symbol_name} #{position.direction.to_s.upcase} @ ₹#{exit_price}",
        meta: {
          symbol: position.instrument.symbol_name,
          exit_price: exit_price,
          exit_reason: reason,
          pnl: pnl,
        }.to_json,
      )

      # Update portfolio equity
      @portfolio.update_equity!
      @portfolio.update_drawdown!

      # Send notification
      send_exit_notification(position, reason, exit_price, pnl)

      log_info("Exited position: #{position.instrument.symbol_name} #{reason} @ ₹#{exit_price}, P&L: ₹#{pnl.round(2)}")
    end

    def send_exit_notification(position, reason, exit_price, pnl)
      return unless Telegram::Notifier.enabled?

      emoji = pnl >= 0 ? "✅" : "❌"
      reason_text = {
        "sl_hit" => "Stop Loss Hit",
        "tp_hit" => "Take Profit Hit",
        "time_based" => "Time-Based Exit",
        "manual" => "Manual Exit",
        "signal_exit" => "Signal Exit",
      }[reason] || reason

      message = "#{emoji} <b>PAPER TRADE EXITED</b>\n\n"
      message += "#{position.instrument.symbol_name} — #{position.direction.to_s.upcase}\n"
      message += "Exit Reason: #{reason_text}\n"
      message += "Entry: ₹#{position.entry_price}\n"
      message += "Exit: ₹#{exit_price}\n"
      message += "Qty: #{position.quantity}\n"
      message += "Holding Days: #{position.holding_days}\n"
      message += "P&L: ₹#{pnl.round(2)} (#{position.pnl_pct}%)\n"
      message += "Portfolio Equity: ₹#{@portfolio.total_equity.round(2)}"

      Telegram::Notifier.send_error_alert(message, context: "Paper Trade Exit")
    rescue StandardError => e
      log_error("Failed to send exit notification: #{e.message}")
    end

    def update_trade_outcome_for_paper_position(position, exit_price:, exit_reason:)
      # Find TradeOutcome by position_id or by symbol + screener_run
      outcome = TradeOutcome.find_by(
        position_id: position.id,
        position_type: "paper_position",
        status: "open",
      )

      # If not found by position_id, try to find by symbol and recent screener run
      unless outcome
        screener_result = ScreenerResult
                          .where(instrument_id: position.instrument_id, symbol: position.symbol)
                          .where("analyzed_at > ?", 1.day.ago)
                          .by_stage("final")
                          .order(analyzed_at: :desc)
                          .first

        if screener_result&.screener_run_id
          outcome = TradeOutcome.find_by(
            screener_run_id: screener_result.screener_run_id,
            instrument_id: position.instrument_id,
            symbol: position.symbol,
            status: "open",
          )
        end
      end

      return unless outcome

      # Map exit reason to TradeOutcome format
      mapped_reason = map_exit_reason(exit_reason)

      TradeOutcomes::Updater.call(
        outcome: outcome,
        exit_price: exit_price,
        exit_reason: mapped_reason,
        exit_time: Time.current,
      )
    rescue StandardError => e
      Rails.logger.error("[PaperTrading::Simulator] Failed to update TradeOutcome: #{e.message}")
      # Don't fail position closing if outcome update fails
    end

    def map_exit_reason(reason)
      case reason.to_s.downcase
      when /target|take.profit|tp|tp_hit/
        "target_hit"
      when /stop|sl|stop.loss|sl_hit/
        "stop_hit"
      when /time|holding|days|time_based/
        "time_based"
      when /signal|invalid|screener|signal_invalidated/
        "signal_invalidated"
      when /manual/
        "manual"
      else
        "manual" # Default to manual if unknown
      end
    end
  end
end
