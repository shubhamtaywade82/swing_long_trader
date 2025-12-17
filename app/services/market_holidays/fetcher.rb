# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "nokogiri"

module MarketHolidays
  # Service to fetch NSE market holidays from NSE website
  # NSE publishes holidays calendar at: https://www.nseindia.com/resources/exchange-communication-holidays
  # Parses HTML table to extract holiday dates and descriptions
  class Fetcher < ApplicationService
    NSE_HOLIDAYS_PAGE_URL = "https://www.nseindia.com/resources/exchange-communication-holidays"
    NSE_API_URL = "https://www.nseindia.com/api/holiday-master"
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

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
      # Try parsing HTML page first (more reliable)
      html_holidays = fetch_from_html_page
      return html_holidays if html_holidays.any?

      # Fallback to API if HTML parsing fails
      api_holidays = fetch_from_api
      return api_holidays if api_holidays.any?

      # Final fallback to manual holidays
      Rails.logger.warn("[MarketHolidays::Fetcher] Both HTML and API failed, using manual holidays")
      fetch_manual_holidays
    rescue StandardError => e
      Rails.logger.warn("[MarketHolidays::Fetcher] Fetch failed: #{e.message}, using manual holidays")
      fetch_manual_holidays
    end

    def fetch_from_html_page
      uri = URI.parse(NSE_HOLIDAYS_PAGE_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 15
      http.open_timeout = 15

      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
      request["Accept-Language"] = "en-US,en;q=0.9"
      request["Accept-Encoding"] = "gzip, deflate, br"
      request["Connection"] = "keep-alive"
      request["Upgrade-Insecure-Requests"] = "1"

      response = http.request(request)

      if response.code == "200"
        parse_html_page(response.body)
      else
        Rails.logger.warn("[MarketHolidays::Fetcher] HTML page returned #{response.code}")
        []
      end
    rescue StandardError => e
      Rails.logger.warn("[MarketHolidays::Fetcher] HTML fetch failed: #{e.message}")
      []
    end

    def fetch_from_api
      uri = URI.parse("#{NSE_API_URL}?type=trading&year=#{@year}")
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
        parse_api_response(response.body)
      else
        Rails.logger.warn("[MarketHolidays::Fetcher] API returned #{response.code}")
        []
      end
    rescue StandardError => e
      Rails.logger.warn("[MarketHolidays::Fetcher] API fetch failed: #{e.message}")
      []
    end

    def parse_html_page(html_body)
      doc = Nokogiri::HTML(html_body)
      holidays = []

      # Strategy 1: Parse tables (most common format)
      doc.css("table").each do |table|
        table_holidays = parse_table(table)
        holidays.concat(table_holidays) if table_holidays.any?
      end

      # Strategy 2: Look for JSON data embedded in scripts
      doc.css("script").each do |script|
        script_holidays = parse_script_json(script.text)
        holidays.concat(script_holidays) if script_holidays.any?
      end

      # Strategy 3: Look for structured data in divs/spans with data attributes
      doc.css("[data-date], [data-holiday-date]").each do |element|
        date_attr = element["data-date"] || element["data-holiday-date"]
        date = parse_date(date_attr)
        if date && date.year == @year
          description = element.text.strip.presence || element["data-description"] || "Market Holiday"
          holidays << { date: date, description: description }
        end
      end

      # Filter to requested year, remove duplicates, and sort
      holidays.uniq { |h| h[:date] }
              .select { |h| h[:date] && h[:date].year == @year }
              .sort_by { |h| h[:date] }
    end

    def parse_table(table)
      holidays = []
      rows = table.css("tr")
      return [] if rows.empty?

      # Check if this table looks like a holidays table
      header_row = rows.first
      header_text = header_row.text.downcase
      return [] unless header_text.include?("date") || header_text.include?("holiday") || header_text.include?("description") || header_text.include?("day")

      # Find column indices for date and description
      header_cells = header_row.css("th, td")
      date_col_index = nil
      desc_col_index = nil

      header_cells.each_with_index do |cell, index|
        cell_text = cell.text.downcase.strip
        date_col_index = index if cell_text.include?("date")
        desc_col_index = index if cell_text.include?("description") || cell_text.include?("holiday") || cell_text.include?("reason")
      end

      # Parse data rows
      rows[1..-1].each do |row|
        cells = row.css("td")
        next if cells.empty?

        date = nil
        description = nil

        # Try to find date in expected column or any column
        if date_col_index && cells[date_col_index]
          date = parse_date(cells[date_col_index].text.strip)
        else
          # Try all cells to find a date
          cells.each do |cell|
            parsed = parse_date(cell.text.strip)
            if parsed && parsed.year == @year
              date = parsed
              break
            end
          end
        end

        # Try to find description
        if desc_col_index && cells[desc_col_index]
          description = cells[desc_col_index].text.strip
        else
          # Find longest text cell that's not a date
          cells.each do |cell|
            cell_text = cell.text.strip
            next if cell_text.blank?
            next if parse_date(cell_text) # Skip if it's a date

            if cell_text.length > description.to_s.length
              description = cell_text
            end
          end
        end

        # Create holiday entry if we found a date
        if date
          description ||= "Market Holiday"
          holidays << { date: date, description: description }
        end
      end

      holidays
    end

    def parse_script_json(script_content)
      holidays = []
      return [] unless script_content.include?("holiday") || script_content.include?("holidays")

      # Try to find JSON objects in script
      # Look for patterns like: {holidays: [...]} or {"holidays": [...]}
      json_patterns = [
        /\{.*?"holidays?"\s*:\s*\[.*?\]/m,
        /\{.*?"data"\s*:\s*\[.*?\]/m,
        /\[.*?\{.*?"date".*?\}.*?\]/m,
      ]

      json_patterns.each do |pattern|
        matches = script_content.scan(pattern)
        matches.each do |match|
          begin
            # Try to extract complete JSON
            json_str = extract_complete_json(match)
            next unless json_str

            data = JSON.parse(json_str)
            api_holidays = parse_api_response(data.to_json)
            holidays.concat(api_holidays) if api_holidays.any?
          rescue JSON::ParserError, StandardError
            # Ignore parse errors and continue
          end
        end
      end

      holidays
    end

    def extract_complete_json(partial_json)
      # Try to balance braces/brackets to get complete JSON
      return nil if partial_json.blank?

      # Simple approach: try to parse as-is, if fails try adding closing braces
      begin
        JSON.parse(partial_json)
        return partial_json
      rescue JSON::ParserError
        # Try adding closing brackets
        balanced = partial_json.dup
        open_braces = balanced.count("{") - balanced.count("}")
        open_brackets = balanced.count("[") - balanced.count("]")

        balanced += "}" * open_braces if open_braces.positive?
        balanced += "]" * open_brackets if open_brackets.positive?

        begin
          JSON.parse(balanced)
          return balanced
        rescue JSON::ParserError
          nil
        end
      end
    end

    def parse_api_response(body)
      data = JSON.parse(body)
      holidays = []

      # NSE API format may vary, handle common structures
      if data.is_a?(Hash) && data["holidays"]
        data["holidays"].each do |holiday|
          date = parse_date(holiday["date"] || holiday["tradingDate"] || holiday["trading_date"])
          description = holiday["description"] || holiday["holiday"] || holiday["name"] || "Market Holiday"
          holidays << { date: date, description: description } if date && date.year == @year
        end
      elsif data.is_a?(Array)
        data.each do |holiday|
          date = parse_date(holiday["date"] || holiday["tradingDate"] || holiday["trading_date"])
          description = holiday["description"] || holiday["holiday"] || holiday["name"] || "Market Holiday"
          holidays << { date: date, description: description } if date && date.year == @year
        end
      elsif data.is_a?(Hash) && data["data"]
        # Handle nested data structure
        (data["data"] || []).each do |holiday|
          date = parse_date(holiday["date"] || holiday["tradingDate"] || holiday["trading_date"])
          description = holiday["description"] || holiday["holiday"] || holiday["name"] || "Market Holiday"
          holidays << { date: date, description: description } if date && date.year == @year
        end
      end

      holidays
    end

    def parse_date(date_string)
      return nil if date_string.blank?

      date_string = date_string.to_s.strip

      # Try various date formats common in NSE pages
      # Formats: "26-Jan-2024", "26/01/2024", "2024-01-26", "Jan 26, 2024", etc.
      date_string = date_string.gsub(/\s+/, " ") # Normalize whitespace

      # Try parsing with common formats
      begin
        # Try standard Date.parse first
        Date.parse(date_string)
      rescue ArgumentError
        # Try DD-MMM-YYYY format (common in Indian sites)
        if date_string.match?(/\d{1,2}-[A-Za-z]{3}-\d{4}/)
          Date.strptime(date_string, "%d-%b-%Y")
        # Try DD/MM/YYYY format
        elsif date_string.match?(/\d{1,2}\/\d{1,2}\/\d{4}/)
          Date.strptime(date_string, "%d/%m/%Y")
        # Try YYYY-MM-DD format
        elsif date_string.match?(/\d{4}-\d{1,2}-\d{1,2}/)
          Date.strptime(date_string, "%Y-%m-%d")
        # Try parsing as timestamp
        elsif date_string.match?(/\A\d+\z/)
          Time.zone.at(date_string.to_i).to_date
        else
          nil
        end
      end
    rescue StandardError => e
      Rails.logger.debug("[MarketHolidays::Fetcher] Failed to parse date '#{date_string}': #{e.message}")
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
