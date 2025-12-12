# frozen_string_literal: true

class IndexConstituent < ApplicationRecord
  validates :company_name, presence: true
  validates :symbol, presence: true
  validates :index_name, presence: true
  validates :symbol, uniqueness: { scope: [:isin_code, :index_name], case_sensitive: false }

  # Scopes for querying
  scope :by_symbol, ->(symbol) { where("UPPER(symbol) = ?", symbol.to_s.upcase) }
  scope :by_isin, ->(isin) { where("UPPER(isin_code) = ?", isin.to_s.upcase) }
  scope :by_index, ->(index) { where("UPPER(index_name) = ?", index.to_s.upcase) }
  scope :by_industry, ->(industry) { where(industry: industry) }
  scope :with_isin, -> { where.not(isin_code: nil) }

  # Get all unique symbols across all indices
  def self.universe_symbols
    distinct.pluck(:symbol).map(&:upcase).to_set
  end

  # Get all unique ISINs across all indices
  def self.universe_isins
    where.not(isin_code: nil).distinct.pluck(:isin_code).map(&:upcase).to_set
  end

  # Check if symbol or ISIN is in universe
  def self.in_universe?(symbol: nil, isin: nil)
    return false if symbol.blank? && isin.blank?

    conditions = []
    conditions << "UPPER(symbol) = ?" if symbol.present?
    conditions << "UPPER(isin_code) = ?" if isin.present?

    values = []
    values << symbol.to_s.upcase if symbol.present?
    values << isin.to_s.upcase if isin.present?

    where(conditions.join(" OR "), *values).exists?
  end
end
