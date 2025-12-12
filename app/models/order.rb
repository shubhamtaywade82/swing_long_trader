# frozen_string_literal: true

class Order < ApplicationRecord
  belongs_to :instrument

  validates :client_order_id, presence: true, uniqueness: true
  validates :symbol, :exchange_segment, :security_id, :product_type, :order_type, :transaction_type, :quantity, presence: true
  validates :transaction_type, inclusion: { in: %w[BUY SELL] }
  validates :order_type, inclusion: { in: %w[MARKET LIMIT SL SL-M] }
  validates :product_type, inclusion: { in: %w[EQUITY MARGIN] }
  validates :status, inclusion: { in: %w[pending placed executed rejected cancelled failed] }
  validates :quantity, numericality: { greater_than: 0 }

  scope :pending, -> { where(status: 'pending') }
  scope :placed, -> { where(status: 'placed') }
  scope :executed, -> { where(status: 'executed') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :failed, -> { where(status: 'failed') }
  scope :active, -> { where(status: %w[pending placed]) }
  scope :dry_run, -> { where(dry_run: true) }
  scope :real, -> { where(dry_run: false) }
  scope :recent, -> { order(created_at: :desc) }
  scope :requires_approval, -> { where(requires_approval: true, approved_at: nil, rejected_at: nil) }
  scope :approved, -> { where.not(approved_at: nil) }
  scope :rejected_for_approval, -> { where.not(rejected_at: nil) }
  scope :pending_approval, -> { where(requires_approval: true).where(approved_at: nil, rejected_at: nil) }

  def metadata_hash
    return {} if metadata.blank?

    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def dhan_response_hash
    return {} if dhan_response.blank?

    JSON.parse(dhan_response)
  rescue JSON::ParserError
    {}
  end

  def pending?
    status == 'pending'
  end

  def placed?
    status == 'placed'
  end

  def executed?
    status == 'executed'
  end

  def cancelled?
    status == 'cancelled'
  end

  def failed?
    status == 'failed'
  end

  def active?
    %w[pending placed].include?(status)
  end

  def buy?
    transaction_type == 'BUY'
  end

  def sell?
    transaction_type == 'SELL'
  end

  def total_value
    (price || 0) * quantity
  end

  def filled_value
    (average_price || 0) * filled_quantity
  end

  def requires_approval?
    requires_approval == true && approved_at.nil? && rejected_at.nil?
  end

  def approved?
    approved_at.present?
  end

  def rejected?
    rejected_at.present?
  end

  def approval_pending?
    requires_approval? && !approved? && !rejected?
  end
end

