# frozen_string_literal: true

module Strategies
  module Swing
    class AnalysisJob < ApplicationJob
      queue_as :default

      def perform(candidate_ids)
        candidates = candidate_ids.map { |id| { instrument_id: id } }
        signals = []

        candidates.each do |candidate|
          result = Evaluator.call(candidate)
          next unless result[:success]

          signal = result[:signal]
          signals << signal

          # Send signal alert to Telegram
          if AlgoConfig.fetch([:notifications, :telegram, :notify_signals])
            Telegram::Notifier.send_signal_alert(signal)
          end
        end

        Rails.logger.info("[Strategies::Swing::AnalysisJob] Generated #{signals.size} signals")

        signals
      rescue StandardError => e
        Rails.logger.error("[Strategies::Swing::AnalysisJob] Failed: #{e.message}")
        Telegram::Notifier.send_error_alert("Swing analysis failed: #{e.message}", context: 'SwingAnalysisJob')
        raise
      end
    end
  end
end

