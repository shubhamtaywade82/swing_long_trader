# frozen_string_literal: true

class PaperLedger < ApplicationRecord
  belongs_to :paper_portfolio
  belongs_to :paper_position, optional: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_type, presence: true, inclusion: { in: %w[credit debit] }
  validates :reason, presence: true

  scope :credits, -> { where(transaction_type: 'credit') }
  scope :debits, -> { where(transaction_type: 'debit') }
  scope :recent, -> { order(created_at: :desc) }

  def credit?
    transaction_type == 'credit'
  end

  def debit?
    transaction_type == 'debit'
  end

  def meta_hash
    return {} if meta.blank?

    JSON.parse(meta)
  rescue JSON::ParserError
    {}
  end
end
