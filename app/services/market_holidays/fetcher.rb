# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module MarketHolidays
  # Service to fetch NSE market holidays from NSE website
  # NSE publishes holidays calendar at: https://www.nseindia.com/market-data/holiday-calendar
  # API endpoint: https://www.nseindia.com/api/holiday-master?type=trading&year=YYYY
  class Fetcher < ApplicationService
    NSE_HOLIDAYS_URL = "https://www.nseindia.com/api/holiday-master"
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

    def self.fetch_and_store(year: nil)
      new(year: year).fetch_and_store
    end

    def initialize(year: nil)
      @year = year || Date.current.year
    end

    def fetch_and_store
      holidays_data = fetch_from_nse
      return { success: false, error: "Failed to fetch holidays from NSE" } if holidays_data.blank?

      stored_count = store_holidays(holidays_data)
      {
        success: true,
        year: @year,
        fetched: holidays_data.size,
        stored: stored_count,
        holidays: holidays_data,
      }
    rescue StandardError => e
      Rails.logger.error("[MarketHolidays::Fetcher] Error fetching holidays: #{e.message}")
      { success: false, error: e.message }
    end

    private

    def fetch_from_nse
      # NSE API requires proper headers and may have CORS/rate limiting
      # Try fetching from their API endpoint
      uri = URI.parse("#{NSE_HOLIDAYS_URL}?type=trading&year=#{@year}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 10
      http.open_timeout = 10

      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = "application/json"
      request["Accept-Language"] = "en-US,en;q=0.9"

      response = http.request(request)

      if response.code == "200"
        parsed = parse_response(response.body)
        return parsed if parsed.any?
      end

      Rails.logger.warn("[MarketHolidays::Fetcher] NSE API returned #{response.code} or empty data, using manual holidays")
      fetch_manual_holidays
    rescue StandardError => e
      Rails.logger.warn("[MarketHolidays::Fetcher] API fetch failed: #{e.message}, using manual holidays")
      fetch_manual_holidays
    end

    def parse_response(body)
      data = JSON.parse(body)
      holidays = []

      # NSE API format may vary, handle common structures
      if data.is_a?(Hash) && data["holidays"]
        data["holidays"].each do |holiday|
          date = parse_date(holiday["date"] || holiday["tradingDate"] || holiday["trading_date"])
          description = holiday["description"] || holiday["holiday"] || holiday["name"] || "Market Holiday"
          holidays << { date: date, description: description } if date
        end
      elsif data.is_a?(Array)
        data.each do |holiday|
          date = parse_date(holiday["date"] || holiday["tradingDate"] || holiday["trading_date"])
          description = holiday["description"] || holiday["holiday"] || holiday["name"] || "Market Holiday"
          holidays << { date: date, description: description } if date
        end
      elsif data.is_a?(Hash) && data["data"]
        # Handle nested data structure
        (data["data"] || []).each do |holiday|
          date = parse_date(holiday["date"] || holiday["tradingDate"] || holiday["trading_date"])
          description = holiday["description"] || holiday["holiday"] || holiday["name"] || "Market Holiday"
          holidays << { date: date, description: description } if date
        end
      end

      holidays
    end

    def parse_date(date_string)
      return nil if date_string.blank?

      # Try various date formats
      Date.parse(date_string.to_s)
    rescue ArgumentError
      # Try parsing as timestamp
      Time.zone.at(date_string.to_i).to_date if date_string.to_s.match?(/\A\d+\z/)
    rescue StandardError
      nil
    end

    def fetch_manual_holidays
      # Fallback: Return common Indian market holidays
      # These can be manually updated or fetched from a reliable source
      # Note: Some holidays vary by year (e.g., Diwali, Good Friday)
      # For accurate dates, manually update or use NSE website
      common_holidays = [
        { date: Date.new(@year, 1, 26), description: "Republic Day" },
        { date: Date.new(@year, 8, 15), description: "Independence Day" },
        { date: Date.new(@year, 10, 2), description: "Gandhi Jayanti" },
        { date: Date.new(@year, 12, 25), description: "Christmas" },
      ]

      # Add variable holidays (approximate dates - should be updated manually)
      # Good Friday calculation (varies by year)
      easter_sunday = calculate_easter(@year)
      good_friday = easter_sunday - 2.days
      common_holidays << { date: good_friday, description: "Good Friday" } if good_friday.year == @year

      # Diwali dates vary significantly - add placeholder
      # TODO: Update with actual Diwali dates from NSE calendar
      # Example for 2024: Diwali is around Nov 1, but varies each year

      # Filter to only include dates in the requested year and weekdays
      common_holidays.select { |h| h[:date].year == @year && (1..5).include?(h[:date].wday) }
    end

    # Calculate Easter Sunday for a given year (for Good Friday calculation)
    # Uses Anonymous Gregorian algorithm
    def calculate_easter(year)
      a = year % 19
      b = year / 100
      c = year % 100
      d = b / 4
      e = b % 4
      f = (b + 8) / 25
      g = (b - f + 1) / 3
      h = (19 * a + b - d - g + 15) % 30
      i = c / 4
      k = c % 4
      l = (32 + 2 * e + 2 * i - h - k) % 7
      m = (a + 11 * h + 22 * l) / 451
      month = (h + l - 7 * m + 114) / 31
      day = ((h + l - 7 * m + 114) % 31) + 1
      Date.new(year, month, day)
    end

    def store_holidays(holidays_data)
      stored = 0
      holidays_data.each do |holiday_data|
        date = holiday_data[:date]
        next unless date.is_a?(Date)

        MarketHoliday.find_or_create_by(date: date) do |holiday|
          holiday.description = holiday_data[:description] || "Market Holiday"
          holiday.year = date.year
        end
        stored += 1
      rescue StandardError => e
        Rails.logger.warn("[MarketHolidays::Fetcher] Failed to store holiday #{date}: #{e.message}")
      end
      stored
    end
  end
end
