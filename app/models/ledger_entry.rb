# frozen_string_literal: true

class LedgerEntry < ApplicationRecord
  belongs_to :portfolio, class_name: "CapitalAllocationPortfolio"
  belongs_to :swing_position, optional: true
  belongs_to :long_term_holding, optional: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :reason, presence: true
  validates :entry_type, inclusion: { in: %w[debit credit] }

  scope :credits, -> { where(entry_type: "credit") }
  scope :debits, -> { where(entry_type: "debit") }
  scope :by_reason, ->(reason) { where(reason: reason) }

  def credit?
    entry_type == "credit"
  end

  def debit?
    entry_type == "debit"
  end

  def metadata_hash
    return {} if metadata.blank?

    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end
end
