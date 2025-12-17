# frozen_string_literal: true

# Model to store NSE market holidays
# Holidays are fetched from NSE website and stored here for efficient lookup
class MarketHoliday < ApplicationRecord
  validates :date, presence: true, uniqueness: true
  validates :description, presence: true

  scope :for_year, ->(year) { where("EXTRACT(YEAR FROM date) = ?", year) }
  scope :upcoming, -> { where("date >= ?", Date.current) }
  scope :past, -> { where("date < ?", Date.current) }

  # Check if a given date is a market holiday
  def self.holiday?(date)
    exists?(date: date.to_date)
  end

  # Get all holidays for a given year
  def self.for_year_array(year)
    for_year(year).pluck(:date).map(&:to_date)
  end

  # Check if today is a market holiday
  def self.today_holiday?
    holiday?(Date.current)
  end
end
