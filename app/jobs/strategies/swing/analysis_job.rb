# frozen_string_literal: true

module Strategies
  module Swing
    class AnalysisJob < ApplicationJob
      # Use background queue for analysis jobs
      queue_as :background

      # Retry strategy: exponential backoff, max 2 attempts
      retry_on StandardError, wait: :polynomially_longer, attempts: 2

      def perform(candidate_ids)
        candidates = candidate_ids.map { |id| { instrument_id: id } }
        signals = []

        candidates.each do |candidate|
          result = Evaluator.call(candidate)
          next unless result[:success]

          signal = result[:signal]
          signals << signal

          # Create signal record (not executed yet, just generated)
          create_signal_record(signal)

          # Send signal alert to Telegram
          Telegram::Notifier.send_signal_alert(signal) if AlgoConfig.fetch(%i[notifications telegram notify_signals])
        end

        Rails.logger.info("[Strategies::Swing::AnalysisJob] Generated #{signals.size} signals")

        signals
      rescue StandardError => e
        Rails.logger.error("[Strategies::Swing::AnalysisJob] Failed: #{e.message}")
        Telegram::Notifier.send_error_alert("Swing analysis failed: #{e.message}", context: "SwingAnalysisJob")
        raise
      end

      private

      def create_signal_record(signal)
        # Get balance information for tracking
        balance_info = get_balance_info_for_signal(signal)

        TradingSignal.create_from_signal(
          signal,
          source: "analysis_job",
          execution_attempted: false,
          balance_info: balance_info,
        )
      rescue StandardError => e
        Rails.logger.error("[Strategies::Swing::AnalysisJob] Failed to create signal record: #{e.message}")
        nil
      end

      def get_balance_info_for_signal(signal)
        if Rails.configuration.x.paper_trading.enabled
          portfolio = PaperTrading::Portfolio.find_or_create_default
          required = signal[:entry_price] * signal[:qty]
          available = portfolio.available_capital
          {
            required: required,
            available: available,
            shortfall: [required - available, 0].max,
            type: "paper_portfolio",
          }
        else
          balance_result = Dhan::Balance.check_available_balance
          required = signal[:entry_price] * signal[:qty]
          available = balance_result[:success] ? balance_result[:balance] : 0
          {
            required: required,
            available: available,
            shortfall: [required - available, 0].max,
            type: "live_account",
          }
        end
      end
    end
  end
end
