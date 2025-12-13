# frozen_string_literal: true

module MarketHours
  # Service to check if Indian stock market is open
  class Checker < ApplicationService
    # NSE market hours: 9:15 AM - 3:30 PM IST, Monday to Friday
    MARKET_OPEN_HOUR = 9
    MARKET_OPEN_MINUTE = 15
    MARKET_CLOSE_HOUR = 15
    MARKET_CLOSE_MINUTE = 30

    # Market hours in IST (for reference)
    # Pre-market: 9:00 AM - 9:15 AM
    # Market open: 9:15 AM - 3:30 PM
    # Post-market: 3:30 PM - 4:00 PM

    def self.market_open?
      new.market_open?
    end

    def self.market_hours?
      new.market_hours?
    end

    def self.trading_day?
      new.trading_day?
    end

    def market_open?
      trading_day? && market_hours?
    end

    def market_hours?
      now = Time.current.in_time_zone("Asia/Kolkata")
      hour = now.hour
      minute = now.min

      # Before market open
      return false if hour < MARKET_OPEN_HOUR
      return false if hour == MARKET_OPEN_HOUR && minute < MARKET_OPEN_MINUTE

      # After market close
      return false if hour > MARKET_CLOSE_HOUR
      return false if hour == MARKET_CLOSE_HOUR && minute > MARKET_CLOSE_MINUTE

      true
    end

    def trading_day?
      now = Time.current.in_time_zone("Asia/Kolkata")
      # Monday = 1, Friday = 5
      (1..5).include?(now.wday)
    end

    def next_market_open
      now = Time.current.in_time_zone("Asia/Kolkata")
      
      # If it's a trading day and before market open, return today's open
      if trading_day? && (now.hour < MARKET_OPEN_HOUR || (now.hour == MARKET_OPEN_HOUR && now.min < MARKET_OPEN_MINUTE))
        return now.change(hour: MARKET_OPEN_HOUR, min: MARKET_OPEN_MINUTE, sec: 0)
      end

      # Otherwise, find next trading day
      days_ahead = 1
      days_ahead += 1 until (now + days_ahead.days).wday.between?(1, 5)
      
      (now + days_ahead.days).change(hour: MARKET_OPEN_HOUR, min: MARKET_OPEN_MINUTE, sec: 0)
    end

    def time_until_market_open
      next_open = next_market_open
      seconds = (next_open - Time.current.in_time_zone("Asia/Kolkata")).to_i
      {
        seconds: seconds,
        minutes: (seconds / 60.0).round(1),
        hours: (seconds / 3600.0).round(2),
        next_open: next_open,
      }
    end
  end
end
