# frozen_string_literal: true

module MarketData
  # Fetches LTP (Last Traded Price) for multiple instruments in a single API call
  # Groups instruments by exchange segment to minimize API calls
  class BulkLtpFetcher < ApplicationService
    def self.call(instruments:)
      new(instruments: instruments).call
    end

    def initialize(instruments:) # rubocop:disable Lint/MissingSuper
      @instruments = Array(instruments)
    end

    def call
      return {} if @instruments.empty?

      # Preload all instrument records in a single query to avoid N+1
      @instrument_lookup = preload_instruments

      # Group instruments by exchange segment
      grouped = group_by_segment

      # Fetch LTPs for each segment
      ltp_map = {}
      grouped.each do |segment, instrument_list|
        segment_ltps = fetch_segment_ltps(segment, instrument_list)
        ltp_map.merge!(segment_ltps)
      end

      ltp_map
    rescue StandardError => e
      Rails.logger.error("[MarketData::BulkLtpFetcher] Failed to fetch bulk LTPs: #{e.message}")
      {}
    end

    private

    def preload_instruments
      # Collect all instrument IDs from hash-based instruments
      instrument_ids = @instruments.filter_map do |instrument|
        if instrument.is_a?(Hash) && instrument[:instrument_id]
          instrument[:instrument_id]
        elsif instrument.respond_to?(:id)
          instrument.id
        end
      end.compact.uniq

      return {} if instrument_ids.empty?

      # Load all instruments in a single query to prevent N+1
      # exchange and segment are enum columns, not associations, so no need to eager load
      instruments = Instrument.where(id: instrument_ids).index_by(&:id)

      # Also add ActiveRecord models that are already loaded
      @instruments.each do |instrument|
        instruments[instrument.id] = instrument if instrument.is_a?(Instrument) && instrument.persisted?
      end

      instruments
    end

    def group_by_segment
      grouped = {}
      @instruments.each do |instrument|
        segment = extract_segment(instrument)
        next unless segment

        grouped[segment] ||= []
        grouped[segment] << instrument
      end
      grouped
    end

    def extract_segment(instrument)
      # Handle different instrument types
      if instrument.is_a?(Hash)
        # From candidate hash: { instrument_id: 123, symbol: "RELIANCE", ... }
        instrument_record = @instrument_lookup[instrument[:instrument_id]] if instrument[:instrument_id]
        return nil unless instrument_record

        instrument_record.exchange_segment if instrument_record.respond_to?(:exchange_segment)
      elsif instrument.respond_to?(:exchange_segment)
        # ActiveRecord model
        instrument.exchange_segment
      else
        nil
      end
    end

    def fetch_segment_ltps(segment, instruments)
      # Build payload: { "NSE_EQ" => [security_id1, security_id2, ...] }
      security_ids = instruments.map do |instrument|
        extract_security_id(instrument)
      end.compact.uniq

      return {} if security_ids.empty?

      segment_enum = segment.to_s.upcase
      payload = { segment_enum => security_ids }

      # Fetch LTPs from DhanHQ API
      response = DhanHQ::Models::MarketFeed.ltp(payload)

      return {} unless response.is_a?(Hash) && response["status"] == "success"

      # Parse response and map to instrument IDs
      data = response.dig("data", segment_enum) || {}
      ltp_map = {}

      instruments.each do |instrument|
        instrument_id = extract_instrument_id(instrument)
        security_id = extract_security_id(instrument)
        next unless instrument_id && security_id

        price_data = data[security_id.to_s]
        ltp = price_data&.dig("last_price") if price_data

        ltp_map[instrument_id] = ltp if ltp
      end

      ltp_map
    rescue StandardError => e
      # Suppress 429 rate limit errors (expected during high load)
      error_msg = e.message.to_s
      is_rate_limit = error_msg.include?("429") || error_msg.include?("rate limit") || error_msg.include?("Rate limit")
      unless is_rate_limit
        Rails.logger.warn("[MarketData::BulkLtpFetcher] Failed to fetch LTPs for segment #{segment}: #{error_msg}")
      end
      {}
    end

    def extract_instrument_id(instrument)
      if instrument.is_a?(Hash)
        instrument[:instrument_id]
      elsif instrument.respond_to?(:id)
        instrument.id
      else
        nil
      end
    end

    def extract_security_id(instrument)
      if instrument.is_a?(Hash)
        # Try to get from instrument record (use preloaded lookup)
        instrument_record = @instrument_lookup[instrument[:instrument_id]] if instrument[:instrument_id]
        return instrument_record.security_id if instrument_record && instrument_record.respond_to?(:security_id)

        # Fallback to security_id in hash
        instrument[:security_id]
      elsif instrument.respond_to?(:security_id)
        instrument.security_id.to_i
      else
        nil
      end
    end
  end
end
