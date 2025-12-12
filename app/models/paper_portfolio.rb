# frozen_string_literal: true

class PaperPortfolio < ApplicationRecord
  has_many :paper_positions, dependent: :destroy
  has_many :paper_ledgers, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :capital, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where.not(name: nil) }

  def metadata_hash
    return {} if metadata.blank?

    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def update_equity!
    # Total equity = capital (which includes realized P&L) + unrealized P&L
    # Capital already includes realized P&L from exits, so we only add unrealized
    update!(
      total_equity: capital + pnl_unrealized,
      available_capital: capital - reserved_capital,
    )
  end

  def update_drawdown!
    return if peak_equity.zero?

    current_equity = total_equity
    drawdown = ((peak_equity - current_equity) / peak_equity * 100).round(2)

    update!(
      max_drawdown: [max_drawdown, drawdown].max,
      peak_equity: [peak_equity, current_equity].max,
    )
  end

  def open_positions
    paper_positions.where(status: "open")
  end

  def closed_positions
    paper_positions.where(status: "closed")
  end

  def total_exposure
    open_positions.sum { |pos| pos.current_price * pos.quantity }
  end

  def utilization_pct
    return 0 if capital.zero?

    (total_exposure / capital * 100).round(2)
  end
end
