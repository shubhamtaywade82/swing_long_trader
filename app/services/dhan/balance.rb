# frozen_string_literal: true

module Dhan
  # Service to check DhanHQ account balance
  class Balance < ApplicationService
    def self.check_available_balance
      new.check_available_balance
    end

    def check_available_balance
      client = get_dhan_client
      return { success: false, error: "DhanHQ client not available", balance: 0 } unless client

      # Get account balance from DhanHQ API
      # Note: This assumes DhanHQ API has a method to get account balance
      # Adjust based on actual DhanHQ API implementation
      begin
        response = client.get_fund_limits || client.get_account_balance || client.get_margin

        if response && response["availableBalance"]
          balance = response["availableBalance"].to_f
          {
            success: true,
            balance: balance,
            currency: "INR",
            raw_response: response,
          }
        elsif response && response["available_margin"]
          balance = response["available_margin"].to_f
          {
            success: true,
            balance: balance,
            currency: "INR",
            raw_response: response,
          }
        else
          # Fallback: try to get from order API or use a default check
          {
            success: false,
            error: "Balance information not available in API response",
            balance: 0,
            raw_response: response,
          }
        end
      rescue StandardError => e
        Rails.logger.error("[Dhan::Balance] Failed to check balance: #{e.message}")
        {
          success: false,
          error: e.message,
          balance: 0,
        }
      end
    end

    def self.has_sufficient_balance?(required_amount)
      result = check_available_balance
      return false unless result[:success]

      result[:balance] >= required_amount
    end

    private

    def get_dhan_client
      require "dhan_hq"
      DhanHQ::Client.new(api_type: :order_api)
    rescue LoadError
      Rails.logger.warn("[Dhan::Balance] DhanHQ gem not installed")
      nil
    rescue StandardError => e
      Rails.logger.error("[Dhan::Balance] Failed to create DhanHQ client: #{e.message}")
      nil
    end
  end
end
