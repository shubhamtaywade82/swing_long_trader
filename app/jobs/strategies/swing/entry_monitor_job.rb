# frozen_string_literal: true

module Strategies
  module Swing
    # Optional job for monitoring entry conditions and placing orders
    # Can be scheduled to run periodically during market hours
    # Checks for new signals and executes them via Executor
    class EntryMonitorJob < ApplicationJob
      include JobLogging

      # Use monitoring queue for entry monitoring
      queue_as :monitoring

      # Retry strategy: exponential backoff, max 2 attempts
      retry_on StandardError, wait: :polynomially_longer, attempts: 2

      def perform(*args)
        # Handle arguments - SolidQueue may pass them as positional or keyword
        # Extract keyword arguments if provided as hash
        opts = if args.any? && args.first.is_a?(Hash)
                 args.first.symbolize_keys
               else
                 {}
               end

        candidate_ids = opts[:candidate_ids] || opts["candidate_ids"]
        dry_run = opts[:dry_run] || opts["dry_run"]

        # Get candidates to monitor
        candidates = if candidate_ids
                       candidate_ids.map { |id| { instrument_id: id } }
                     else
                       # Get top candidates from screener
                       get_top_candidates(limit: 10)
                     end

        signals = []
        orders_placed = []

        candidates.each do |candidate|
          # Evaluate candidate for entry signal
          result = Evaluator.call(candidate)
          next unless result[:success]

          signal = result[:signal]
          signals << signal

          # Check if we should execute (not already in position, risk checks pass, etc.)
          if should_execute?(signal)
            # Execute order via Executor
            execution_result = Executor.call(signal, dry_run: dry_run)

            if execution_result[:success]
              orders_placed << execution_result[:order]
              Rails.logger.info(
                "[Strategies::Swing::EntryMonitorJob] Order placed: " \
                "#{signal[:symbol]} #{signal[:direction]} #{signal[:qty]} @ #{signal[:entry_price]}",
              )
            else
              Rails.logger.warn(
                "[Strategies::Swing::EntryMonitorJob] Order rejected: " \
                "#{signal[:symbol]} - #{execution_result[:error]}",
              )
            end
          else
            Rails.logger.debug do
              "[Strategies::Swing::EntryMonitorJob] Signal not executed: #{signal[:symbol]} " \
                "(already in position or risk check failed)"
            end
          end
        rescue StandardError => e
          Rails.logger.error(
            "[Strategies::Swing::EntryMonitorJob] Failed for candidate #{candidate[:instrument_id]}: #{e.message}",
          )
        end

        Rails.logger.info(
          "[Strategies::Swing::EntryMonitorJob] Completed: " \
          "signals=#{signals.size}, " \
          "orders_placed=#{orders_placed.size}",
        )

        {
          signals: signals,
          orders_placed: orders_placed,
        }
      rescue StandardError => e
        Rails.logger.error("[Strategies::Swing::EntryMonitorJob] Failed: #{e.message}")
        Telegram::Notifier.send_error_alert("Entry monitor failed: #{e.message}", context: "EntryMonitorJob")
        raise
      end

      private

      def should_execute?(signal)
        # Check if already in position for this instrument
        return false if already_in_position?(signal[:instrument_id])

        # Additional checks can be added here:
        # - Market hours check
        # - Risk limits check (handled by Executor)
        # - Signal confidence threshold
        # - etc.

        true
      end

      def already_in_position?(instrument_id)
        # Check if there's an active order or position for this instrument
        Order.exists?(instrument_id: instrument_id, status: %w[pending placed])
      end

      def get_top_candidates(limit: 10)
        # Get top candidates from recent screener run
        # In production, you might want to query stored screener results
        universe_file = Rails.root.join("config/universe/master_universe.yml")
        if universe_file.exist?
          universe_data = YAML.load_file(universe_file)
          return [] if universe_data.blank?

          # Extract symbol strings from YAML structure (handles both array of hashes and array of strings)
          universe_symbols = if universe_data.first.is_a?(Hash)
                               universe_data.map { |item| item[:symbol] || item["symbol"] }.compact
                             else
                               universe_data
                             end

          # Ensure we have an array of strings (not hashes or other objects)
          universe_symbols = universe_symbols.select { |s| s.is_a?(String) }
          return [] if universe_symbols.empty?

          instruments = Instrument.where(symbol_name: universe_symbols).limit(limit)
          instruments.map { |inst| { instrument_id: inst.id } }
        else
          []
        end
      end
    end
  end
end
