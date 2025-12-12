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

      # Check risk limits
      risk_check = PaperTrading::RiskManager.check_limits(portfolio: @portfolio, signal: @signal)
      return risk_check unless risk_check[:success]

      # Create position
      position = PaperTrading::Position.create!(
        portfolio: @portfolio,
        instrument: @instrument,
        signal: @signal,
      )

      # Send notification
      send_entry_notification(position)

      {
        success: true,
        position: position,
        message: "Paper trade executed: #{@instrument.symbol_name} #{@signal[:direction].to_s.upcase}",
      }
    rescue StandardError => e
      log_error("Paper trade execution failed: #{e.message}")
      {
        success: false,
        error: e.message,
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
  end
end
