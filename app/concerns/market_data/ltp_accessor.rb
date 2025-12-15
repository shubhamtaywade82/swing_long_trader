# frozen_string_literal: true

module MarketData
  # Concern to easily access LTPs in models and services
  # Include this module to add convenient LTP access methods
  #
  # Usage in a model:
  #   class Instrument < ApplicationRecord
  #     include MarketData::LtpAccessor
  #   end
  #
  #   instrument = Instrument.find(1)
  #   ltp = instrument.current_ltp  # => 1234.56 or nil
  #
  # Usage in a service:
  #   class SomeService
  #     include MarketData::LtpAccessor
  #
  #     def call
  #       ltp = current_ltp_for("NSE_EQ", "1333")
  #       # ...
  #     end
  #   end
  module LtpAccessor
    extend ActiveSupport::Concern

    # Get current LTP for this model instance (if it responds to exchange_segment and security_id)
    # @return [Float, nil] Current LTP or nil if not cached
    def current_ltp
      return nil unless respond_to?(:exchange_segment) && respond_to?(:security_id)

      MarketData::LtpCache.get(exchange_segment, security_id)
    end

    # Get current LTP for a segment and security_id
    # @param segment [String] Exchange segment
    # @param security_id [String, Integer] Security ID
    # @return [Float, nil] Current LTP or nil if not cached
    def current_ltp_for(segment, security_id)
      MarketData::LtpCache.get(segment, security_id)
    end

    # Get multiple LTPs efficiently
    # @param instruments [Array<Array<String, String>>] Array of [segment, security_id] pairs
    # @return [Hash<String, Float>] Hash with keys like "NSE_EQ:1333" => 1234.56
    def current_ltps_for(instruments)
      MarketData::LtpCache.get_multiple(instruments)
    end

    # Check if LTP is cached for this model instance
    # @return [Boolean] True if LTP is cached
    def ltp_cached?
      return false unless respond_to?(:exchange_segment) && respond_to?(:security_id)

      MarketData::LtpCache.cached?(exchange_segment, security_id)
    end
  end
end
