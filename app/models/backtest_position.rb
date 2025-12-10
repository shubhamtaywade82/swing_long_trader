# frozen_string_literal: true

class BacktestPosition < ApplicationRecord
  belongs_to :backtest_run
  belongs_to :instrument

  validates :entry_date, :direction, :entry_price, :quantity, presence: true
  validates :direction, inclusion: { in: %w[long short] }

  scope :long, -> { where(direction: 'long') }
  scope :short, -> { where(direction: 'short') }
  scope :closed, -> { where.not(exit_date: nil) }
  scope :open, -> { where(exit_date: nil) }

  def closed?
    exit_date.present?
  end

  def open?
    exit_date.nil?
  end

  def calculate_pnl
    return 0 unless closed?

    case direction
    when 'long'
      (exit_price - entry_price) * quantity
    when 'short'
      (entry_price - exit_price) * quantity
    else
      0
    end
  end

  def calculate_pnl_pct
    return 0 unless closed?

    case direction
    when 'long'
      ((exit_price - entry_price) / entry_price * 100).round(4)
    when 'short'
      ((entry_price - exit_price) / entry_price * 100).round(4)
    else
      0
    end
  end
end

