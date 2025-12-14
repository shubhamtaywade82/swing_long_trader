# frozen_string_literal: true

module PaperTrading
  # Executes paper trading signals
  class Executor < ApplicationService
    def self.execute(signal, portfolio: nil)
      portfolio ||= PaperTrading::Portfolio.find_or_create_default
      new(signal: signal, portfolio: portfolio).execute
    end

    def initialize(signal:, portfolio:)
      @signal = signal
      @portfolio = portfolio
      @instrument = Instrument.find_by(id: signal[:instrument_id])
    end

    def execute
      # Validate signal
      validation = validate_signal
      return validation unless validation[:success]

      # Create or find signal record
      signal_record = find_or_create_signal_record

      # Check risk limits
      risk_check = PaperTrading::RiskManager.check_limits(portfolio: @portfolio, signal: @signal)
      unless risk_check[:success]
        signal_record&.mark_as_not_executed!(
          reason: risk_check[:error],
          metadata: { risk_check: risk_check },
        )
        return risk_check
      end

      # Create position
      position = PaperTrading::Position.create!(
        portfolio: @portfolio,
        instrument: @instrument,
        signal: @signal,
      )

      # Create TradeOutcome if this is from a screener run
      create_trade_outcome_if_from_screener(position, signal_record)

      # Update signal record as executed
      signal_record&.mark_as_executed!(
        execution_type: "paper",
        paper_position: position,
        metadata: { portfolio_id: @portfolio.id },
      )

      # Send notification
      send_entry_notification(position)

      {
        success: true,
        position: position,
        paper_trade: true,
        message: "Paper trade executed: #{@instrument.symbol_name} #{@signal[:direction].to_s.upcase}",
      }
    rescue StandardError => e
      log_error("Paper trade execution failed: #{e.message}")
      signal_record&.mark_as_failed!(
        reason: "Execution failed",
        error: e.message,
        metadata: { exception: e.class.name },
      )
      {
        success: false,
        error: e.message,
        paper_trade: true,
      }
    end

    private

    def validate_signal
      return { success: false, error: "Invalid signal" } if @signal.blank?
      return { success: false, error: "Instrument not found" } if @instrument.blank?
      return { success: false, error: "Missing entry price" } unless @signal[:entry_price]
      return { success: false, error: "Missing quantity" } unless @signal[:qty]
      return { success: false, error: "Missing direction" } unless @signal[:direction]

      { success: true }
    end

    def find_or_create_signal_record
      # Try to find existing signal record (created by swing executor)
      signal_record = TradingSignal.where(
        instrument_id: @instrument.id,
        symbol: @signal[:symbol] || @instrument.symbol_name,
        direction: @signal[:direction].to_s,
        entry_price: @signal[:entry_price],
        quantity: @signal[:qty],
      ).where("signal_generated_at > ?", 5.minutes.ago).order(signal_generated_at: :desc).first

      # If not found, create one
      unless signal_record
        balance_info = {
          required: @signal[:entry_price] * @signal[:qty],
          available: @portfolio.available_capital,
          shortfall: [(@signal[:entry_price] * @signal[:qty]) - @portfolio.available_capital, 0].max,
          type: "paper_portfolio",
        }

        signal_record = TradingSignal.create_from_signal(
          @signal,
          source: "paper_executor",
          execution_attempted: true,
          balance_info: balance_info,
        )
      end

      signal_record
    rescue StandardError => e
      log_error("Failed to find or create signal record: #{e.message}")
      nil
    end

    def send_entry_notification(_position)
      return unless Telegram::Notifier.enabled?

      message = "📘 <b>PAPER TRADE EXECUTED</b>\n\n"
      message += "#{@instrument.symbol_name} — #{@signal[:direction].to_s.upcase}\n"
      message += "Entry: ₹#{@signal[:entry_price]}\n"
      message += "SL: ₹#{@signal[:sl]}\n" if @signal[:sl]
      message += "TP: ₹#{@signal[:tp]}\n" if @signal[:tp]
      message += "Qty: #{@signal[:qty]}\n"
      message += "Capital Used: ₹#{(@signal[:entry_price] * @signal[:qty]).round(2)}\n"
      message += "Portfolio Remaining: ₹#{@portfolio.available_capital.round(2)}\n"
      message += "Total Equity: ₹#{@portfolio.total_equity.round(2)}"

      Telegram::Notifier.send_error_alert(message, context: "Paper Trade Entry")
    rescue StandardError => e
      log_error("Failed to send entry notification: #{e.message}")
    end

    def create_trade_outcome_if_from_screener(position, signal_record)
      # Check if signal came from a screener run
      return unless signal_record

      # Try to find screener_run_id from signal metadata
      metadata = signal_record.metadata_hash || {}
      screener_run_id = metadata["screener_run_id"] || metadata[:screener_run_id]

      # If no screener_run_id, check if signal has screener_run_id attribute
      screener_run_id ||= signal_record.respond_to?(:screener_run_id) ? signal_record.screener_run_id : nil

      # If still no screener_run_id, try to find from recent screener results
      unless screener_run_id
        screener_result = ScreenerResult
                          .where(instrument_id: @instrument.id, symbol: @signal[:symbol] || @instrument.symbol_name)
                          .where("analyzed_at > ?", 1.hour.ago)
                          .by_stage("final")
                          .order(analyzed_at: :desc)
                          .first

        screener_run_id = screener_result&.screener_run_id
      end

      return unless screener_run_id

      # Find screener run
      screener_run = ScreenerRun.find_by(id: screener_run_id)
      return unless screener_run

      # Get candidate data from screener result
      screener_result = screener_run.screener_results
                                     .find_by(instrument_id: @instrument.id)

      return unless screener_result

      # Create TradeOutcome
      candidate_hash = screener_result.to_candidate_hash.merge(
        tier: metadata["tier"] || metadata[:tier] || "tier_1",
        stage: "final",
      )

      result = TradeOutcomes::Creator.call(
        screener_run: screener_run,
        candidate: candidate_hash,
        position: position,
        trading_mode: "paper",
      )

      if result[:success]
        log_info("Created TradeOutcome for paper position #{position.id} from screener run ##{screener_run_id}")
      else
        log_error("Failed to create TradeOutcome: #{result[:error]}")
      end
    rescue StandardError => e
      log_error("Failed to create TradeOutcome from screener: #{e.message}")
      # Don't fail position creation if outcome creation fails
    end
  end
end
