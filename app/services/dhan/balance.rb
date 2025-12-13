# frozen_string_literal: true

module Dhan
  # Service to check DhanHQ account balance
  class Balance < ApplicationService
    def self.check_available_balance
      new.check_available_balance
    end

    def self.has_sufficient_balance?(required_amount)
      result = check_available_balance
      return false unless result[:success]

      result[:balance] >= required_amount
    end

    def check_available_balance
      require "dhan_hq"

      # Use DhanHQ::Models::Funds.fetch to get balance
      funds = DhanHQ::Models::Funds.fetch

      # Extract available balance from funds response
      # Try multiple possible field names and formats
      available_balance = extract_balance_from_funds(funds)

      if available_balance.positive?
        {
          success: true,
          balance: available_balance,
          currency: "INR",
          raw_response: funds_to_hash(funds),
        }
      else
        Rails.logger.warn("[Dhan::Balance] Available balance is 0 or not found in response")
        {
          success: false,
          error: "Balance information not available or zero",
          balance: 0,
          raw_response: funds_to_hash(funds),
        }
      end
    rescue LoadError => e
      Rails.logger.error("[Dhan::Balance] DhanHQ gem not installed: #{e.message}")
      {
        success: false,
        error: "DhanHQ gem not installed",
        balance: 0,
      }
    rescue StandardError => e
      Rails.logger.error("[Dhan::Balance] Failed to check balance: #{e.message}")
      Rails.logger.error("[Dhan::Balance] Backtrace: #{e.backtrace.first(5).join("\n")}")
      {
        success: false,
        error: e.message,
        balance: 0,
      }
    end

    private

    def extract_balance_from_funds(funds)
      # DhanHQ::Models::Funds responds to available_balance directly
      return funds.available_balance.to_f if funds.respond_to?(:available_balance)

      # Fallback to other possible method names
      return funds.availableBalance.to_f if funds.respond_to?(:availableBalance)
      return funds.available.to_f if funds.respond_to?(:available)
      return funds.balance.to_f if funds.respond_to?(:balance)

      # Try hash access
      if funds.is_a?(Hash)
        return funds["available_balance"].to_f if funds["available_balance"]
        return funds["availableBalance"].to_f if funds["availableBalance"]
        return funds[:available_balance].to_f if funds[:available_balance]
        return funds[:availableBalance].to_f if funds[:availableBalance]
        return funds["available"].to_f if funds["available"]
        return funds[:available].to_f if funds[:available]
        return funds["balance"].to_f if funds["balance"]
        return funds[:balance].to_f if funds[:balance]
      end

      # Try converting to hash
      if funds.respond_to?(:to_h)
        funds_hash = funds.to_h
        return funds_hash["available_balance"].to_f if funds_hash["available_balance"]
        return funds_hash["availableBalance"].to_f if funds_hash["availableBalance"]
        return funds_hash[:available_balance].to_f if funds_hash[:available_balance]
        return funds_hash[:availableBalance].to_f if funds_hash[:availableBalance]
        return funds_hash["available"].to_f if funds_hash["available"]
        return funds_hash[:available].to_f if funds_hash[:available]
        return funds_hash["balance"].to_f if funds_hash["balance"]
        return funds_hash[:balance].to_f if funds_hash[:balance]
      end

      # Try attributes if it's an object
      if funds.respond_to?(:attributes)
        attrs = funds.attributes
        return attrs["available_balance"].to_f if attrs["available_balance"]
        return attrs["availableBalance"].to_f if attrs["availableBalance"]
        return attrs[:available_balance].to_f if attrs[:available_balance]
        return attrs[:availableBalance].to_f if attrs[:availableBalance]
      end

      # Log the actual structure for debugging
      Rails.logger.warn("[Dhan::Balance] Could not extract balance. Funds type: #{funds.class}, methods: #{funds.respond_to?(:methods) ? funds.methods.grep(/balance|available|fund/).join(', ') : 'N/A'}")
      0
    end

    def funds_to_hash(funds)
      return funds if funds.is_a?(Hash)
      return funds.to_h if funds.respond_to?(:to_h)
      return funds.attributes if funds.respond_to?(:attributes)

      funds.inspect
    end
  end
end
