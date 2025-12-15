# frozen_string_literal: true

module DhanHelper
  extend ActiveSupport::Concern

  private

  # Parses DhanHQ date strings into Time objects
  # Supports formats: "14/12/2025 19:08" and "2025-12-26 00:00:00.0"
  # @param [String, nil] date_string Date string from DhanHQ API
  # @return [Time, nil] Parsed time object or nil if invalid
  def parse_dhan_date(date_string)
    return nil unless date_string.present?

    # Try parsing formats like "14/12/2025 19:08" or "2025-12-26 00:00:00.0"
    if date_string.match?(%r{\d{2}/\d{2}/\d{4}})
      # Format: "14/12/2025 19:08"
      parts = date_string.split
      date_part = parts[0]
      time_part = parts[1] || "00:00"
      day, month, year = date_part.split("/").map(&:to_i)
      hour, minute = time_part.split(":").map(&:to_i)
      Time.zone.local(year, month, day, hour, minute)
    elsif date_string.match?(/\d{4}-\d{2}-\d{2}/)
      # Format: "2025-12-26 00:00:00.0"
      Time.zone.parse(date_string)
    else
      nil
    end
  rescue StandardError => e
    Rails.logger.warn("[DhanHelper] Failed to parse date '#{date_string}': #{e.message}")
    nil
  end
end
