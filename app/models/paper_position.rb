# frozen_string_literal: true

class PaperPosition < ApplicationRecord
  belongs_to :paper_portfolio
  belongs_to :instrument

  validates :direction, presence: true, inclusion: { in: %w[long short] }
  validates :entry_price, :current_price, :quantity, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[open closed] }

  scope :open, -> { where(status: 'open') }
  scope :closed, -> { where(status: 'closed') }
  scope :long, -> { where(direction: 'long') }
  scope :short, -> { where(direction: 'short') }
  scope :recent, -> { order(opened_at: :desc) }

  def metadata_hash
    return {} if metadata.blank?

    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def open?
    status == 'open'
  end

  def closed?
    status == 'closed'
  end

  def long?
    direction == 'long'
  end

  def short?
    direction == 'short'
  end

  def entry_value
    entry_price * quantity
  end

  def current_value
    current_price * quantity
  end

  def unrealized_pnl
    if long?
      (current_price - entry_price) * quantity
    else
      (entry_price - current_price) * quantity
    end
  end

  def unrealized_pnl_pct
    return 0 if entry_price.zero?

    if long?
      ((current_price - entry_price) / entry_price * 100).round(2)
    else
      ((entry_price - current_price) / entry_price * 100).round(2)
    end
  end

  def realized_pnl
    return 0 unless closed? && exit_price

    if long?
      (exit_price - entry_price) * quantity
    else
      (entry_price - exit_price) * quantity
    end
  end

  def realized_pnl_pct
    return 0 unless closed? && exit_price

    if long?
      ((exit_price - entry_price) / entry_price * 100).round(2)
    else
      ((entry_price - exit_price) / entry_price * 100).round(2)
    end
  end

  def update_current_price!(price)
    update!(current_price: price.to_f)
    update_unrealized_pnl!
  end

  def update_unrealized_pnl!
    return unless open?

    pnl = unrealized_pnl
    pnl_pct = unrealized_pnl_pct

    update!(pnl: pnl, pnl_pct: pnl_pct)
  end

  def check_sl_hit?
    return false unless sl

    if long?
      current_price <= sl
    else
      current_price >= sl
    end
  end

  def check_tp_hit?
    return false unless tp

    if long?
      current_price >= tp
    else
      current_price <= tp
    end
  end

  def days_held
    return 0 unless opened_at

    ((Time.current - opened_at) / 1.day).floor
  end
end
