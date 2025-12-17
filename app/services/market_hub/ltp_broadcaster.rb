# frozen_string_literal: true

module MarketHub
  # Service to fetch and broadcast real-time LTPs for screener stocks
  class LtpBroadcaster < ApplicationService
    BATCH_SIZE = 50 # Fetch LTPs in batches to avoid API rate limits

    def initialize(screener_type: nil, instrument_ids: nil, symbols: nil)
      @screener_type = screener_type
      @instrument_ids = instrument_ids
      @symbols = symbols
    end

    def call
      instruments = fetch_instruments
      return { success: false, error: "No instruments found" } if instruments.empty?

      ltp_data = fetch_ltps(instruments)
      broadcast_updates(ltp_data)

      {
        success: true,
        updated_count: ltp_data.size,
        timestamp: Time.current,
      }
    rescue StandardError => e
      Rails.logger.error("[MarketHub::LtpBroadcaster] Error: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      { success: false, error: e.message }
    end

    private

    def fetch_instruments
      if @instrument_ids.present?
        Instrument.where(id: @instrument_ids)
      elsif @symbols.present?
        Instrument.where(symbol_name: @symbols)
      elsif @screener_type.present?
        # Get latest screener results for this type
        latest_results = ScreenerResult.latest_for(screener_type: @screener_type, limit: 200)
        instrument_ids = latest_results.pluck(:instrument_id).compact.uniq
        Instrument.where(id: instrument_ids)
      else
        # Default: get latest swing screener results
        latest_results = ScreenerResult.latest_for(screener_type: "swing", limit: 200)
        instrument_ids = latest_results.pluck(:instrument_id).compact.uniq
        Instrument.where(id: instrument_ids)
      end
    end

    def fetch_ltps(instruments)
      ltp_data = {}
      instruments.in_batches(of: BATCH_SIZE) do |batch|
        batch.each do |instrument|
          ltp = instrument.ltp
          next unless ltp.present? && ltp.to_f.positive?

          instrument_key = "#{instrument.exchange_segment}:#{instrument.security_id}"
          ltp_data[instrument.id] = {
            instrument_id: instrument.id,
            symbol: instrument.symbol_name,
            instrument_key: instrument_key, # Format: "NSE_EQ:1333" - matches data-instrument-key attribute
            ltp: ltp.to_f,
            timestamp: Time.current,
          }
        rescue StandardError => e
          Rails.logger.warn("[MarketHub::LtpBroadcaster] Failed to fetch LTP for #{instrument.symbol_name}: #{e.message}")
        end

        # Small delay between batches to avoid rate limiting
        sleep(0.1) if instruments.count > BATCH_SIZE
      end

      ltp_data
    end

    def broadcast_updates(ltp_data)
      return if ltp_data.empty?

      # Broadcast individual updates for each symbol
      ltp_data.each_value do |data|
        ActionCable.server.broadcast(
          "dashboard_updates",
          {
            type: "screener_ltp_update",
            symbol: data[:symbol],
            instrument_id: data[:instrument_id],
            ltp: data[:ltp],
            timestamp: data[:timestamp].iso8601,
          },
        )
      end

      # Also broadcast batch update for efficiency
      ActionCable.server.broadcast(
        "dashboard_updates",
        {
          type: "screener_ltp_batch_update",
          updates: ltp_data.values,
          timestamp: Time.current.iso8601,
        },
      )
    end
  end
end
