# frozen_string_literal: true

module Candles
  # Optional job for on-demand intraday candle fetching
  # Can be scheduled or triggered manually for top candidates
  class IntradayFetcherJob < ApplicationJob
    include JobLogging

    queue_as :default

    def perform(instrument_ids: nil, interval: '15')
      instruments = if instrument_ids
                     Instrument.where(id: instrument_ids)
                   else
                     # Default: fetch for top 20 screener candidates
                     get_top_candidates(limit: 20)
                   end

      results = {
        processed: 0,
        success: 0,
        failed: 0,
        errors: []
      }

      instruments.find_each do |instrument|
        begin
          # Fetch intraday candles (in-memory, not stored)
          series = IntradayFetcher.call(instrument: instrument, interval: interval)
          results[:processed] += 1

          if series&.candles&.any?
            results[:success] += 1
            Rails.logger.debug(
              "[Candles::IntradayFetcherJob] Fetched #{series.candles.size} " \
              "#{interval}min candles for #{instrument.symbol_name}"
            )
          else
            results[:failed] += 1
            results[:errors] << { instrument: instrument.symbol_name, error: 'No candles returned' }
          end
        rescue StandardError => e
          results[:failed] += 1
          results[:errors] << { instrument: instrument.symbol_name, error: e.message }
          Rails.logger.error(
            "[Candles::IntradayFetcherJob] Failed for #{instrument.symbol_name}: #{e.message}"
          )
        end
      end

      Rails.logger.info(
        "[Candles::IntradayFetcherJob] Completed: " \
        "processed=#{results[:processed]}, " \
        "success=#{results[:success]}, " \
        "failed=#{results[:failed]}"
      )

      results
    rescue StandardError => e
      Rails.logger.error("[Candles::IntradayFetcherJob] Failed: #{e.message}")
      Telegram::Notifier.send_error_alert("Intraday fetcher failed: #{e.message}", context: 'IntradayFetcherJob')
      raise
    end

    private

    def get_top_candidates(limit: 20)
      # Get top candidates from recent screener run
      # This is a simple implementation - in production, you might want to
      # store screener results and query them
      universe_file = Rails.root.join('config/universe/master_universe.yml')
      if universe_file.exist?
        universe_symbols = YAML.load_file(universe_file).to_set
        Instrument.where(symbol_name: universe_symbols.to_a).limit(limit)
      else
        Instrument.where(instrument_type: ['EQUITY', 'INDEX']).limit(limit)
      end
    end
  end
end

