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

    # Check if a date is a trading day (weekday and not a holiday)
    # @param date [Date, Time, nil] Date to check (defaults to current time)
    # @return [Boolean] true if trading day, false otherwise
    def trading_day?(date = nil)
      date ||= Time.current.in_time_zone("Asia/Kolkata")
      date = date.to_date if date.is_a?(Time) || date.is_a?(ActiveSupport::TimeWithZone)

      # Must be a weekday (Monday = 1, Friday = 5)
      return false unless (1..5).include?(date.wday)

      # Must not be a market holiday
      return false if MarketHoliday.holiday?(date)

      true
    end

    def next_market_open
      now = Time.current.in_time_zone("Asia/Kolkata")

      # If it's a trading day and before market open, return today's open
      if trading_day? && (now.hour < MARKET_OPEN_HOUR || (now.hour == MARKET_OPEN_HOUR && now.min < MARKET_OPEN_MINUTE))
        return now.change(hour: MARKET_OPEN_HOUR, min: MARKET_OPEN_MINUTE, sec: 0)
      end

      # Otherwise, find next trading day (skip weekends and holidays)
      days_ahead = 1
      loop do
        candidate_date = (now + days_ahead.days).to_date
        break if trading_day?(candidate_date)
        days_ahead += 1
        raise "Could not find next trading day within 30 days" if days_ahead > 30
      end

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
