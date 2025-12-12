# frozen_string_literal: true

class Position < ApplicationRecord
  belongs_to :instrument
  belongs_to :order # Entry order
  belongs_to :exit_order, class_name: "Order", optional: true
  belongs_to :trading_signal, optional: true

  validates :symbol, :direction, :entry_price, :current_price, :quantity, :opened_at, presence: true, unless: :portfolio?
  validates :direction, inclusion: { in: %w[long short] }, allow_nil: true
  validates :status, inclusion: { in: %w[open closed partially_closed] }
  validates :quantity, numericality: { greater_than: 0 }, allow_nil: true
  validates :trading_mode, inclusion: { in: %w[live paper] }, allow_nil: true

  belongs_to :paper_portfolio, optional: true # For backward compatibility

  scope :live, -> { where(trading_mode: "live").or(where(trading_mode: nil)) } # nil defaults to live
  scope :paper, -> { where(trading_mode: "paper") }
  scope :by_trading_mode, ->(mode) { where(trading_mode: mode) }

  def portfolio?
    type == "Portfolio"
  end

  def live?
    trading_mode.nil? || trading_mode == "live"
  end

  def paper?
    trading_mode == "paper"
  end

  scope :open, -> { where(status: "open") }
  scope :closed, -> { where(status: "closed") }
  scope :active, -> { where(status: %w[open partially_closed]) }
  scope :long, -> { where(direction: "long") }
  scope :short, -> { where(direction: "short") }
  scope :recent, -> { order(opened_at: :desc) }
  scope :synced, -> { where(synced_with_dhan: true) }
  scope :not_synced, -> { where(synced_with_dhan: false) }
  scope :by_symbol, ->(symbol) { where(symbol: symbol) }
  scope :regular_positions, -> { where(type: [nil, "Position"]) }
  scope :portfolios, -> { where(type: "Portfolio") }
  scope :by_portfolio_date, ->(date) { where(portfolio_date: date) }
  scope :continued, -> { where(continued_from_previous_day: true) }
  scope :new_today, -> { where(continued_from_previous_day: false) }

  def metadata_hash
    return {} if metadata.blank?

    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def sync_metadata_hash
    return {} if sync_metadata.blank?

    JSON.parse(sync_metadata)
  rescue JSON::ParserError
    {}
  end

  def dhan_position_data_hash
    return {} if dhan_position_data.blank?

    JSON.parse(dhan_position_data)
  rescue JSON::ParserError
    {}
  end

  def open?
    status == "open"
  end

  def closed?
    status == "closed"
  end

  def partially_closed?
    status == "partially_closed"
  end

  def long?
    direction == "long"
  end

  def short?
    direction == "short"
  end

  def entry_value
    (average_entry_price || entry_price) * quantity
  end

  def current_value
    current_price * quantity
  end

  def calculate_unrealized_pnl
    if long?
      pnl = (current_price - entry_price) * quantity
    else
      pnl = (entry_price - current_price) * quantity
    end

    pnl_pct = if entry_price.positive?
                (pnl / entry_value * 100).round(2)
              else
                0
              end

    {
      pnl: pnl.round(2),
      pnl_pct: pnl_pct,
    }
  end

  def update_unrealized_pnl!
    result = calculate_unrealized_pnl
    update!(
      unrealized_pnl: result[:pnl],
      unrealized_pnl_pct: result[:pnl_pct],
    )
  end

  def calculate_realized_pnl
    return { pnl: 0, pnl_pct: 0 } unless closed? && exit_price

    if long?
      pnl = (exit_price - entry_price) * quantity
    else
      pnl = (entry_price - exit_price) * quantity
    end

    pnl_pct = if entry_price.positive?
                (pnl / entry_value * 100).round(2)
              else
                0
              end

    {
      pnl: pnl.round(2),
      pnl_pct: pnl_pct,
    }
  end

  def days_held
    return 0 unless opened_at

    end_date = closed_at || Time.current
    ((end_date - opened_at) / 1.day).floor
  end

  def check_sl_hit?
    return false unless stop_loss && open?

    if long?
      current_price <= stop_loss
    else
      current_price >= stop_loss
    end
  end

  def check_tp_hit?
    return false unless take_profit && open?

    if long?
      current_price >= take_profit
    else
      current_price <= take_profit
    end
  end

  def check_trailing_stop?
    return false unless trailing_stop_distance || trailing_stop_pct
    return false unless open?

    if long?
      return false unless highest_price

      trailing_stop = if trailing_stop_pct
                        highest_price * (1 - (trailing_stop_pct / 100.0))
                      else
                        highest_price - trailing_stop_distance
                      end

      current_price <= trailing_stop
    else
      return false unless lowest_price

      trailing_stop = if trailing_stop_pct
                        lowest_price * (1 + (trailing_stop_pct / 100.0))
                      else
                        lowest_price + trailing_stop_distance
                      end

      current_price >= trailing_stop
    end
  end

  def update_highest_lowest_price!
    return unless open?

    if long?
      update!(highest_price: [highest_price || entry_price, current_price].max)
    else
      update!(lowest_price: [lowest_price || entry_price, current_price].min)
    end
  end

  def mark_as_closed!(exit_price:, exit_reason:, exit_order: nil)
    pnl_result = if long?
                   { pnl: (exit_price - entry_price) * quantity, pnl_pct: ((exit_price - entry_price) / entry_price * 100).round(2) }
                 else
                   { pnl: (entry_price - exit_price) * quantity, pnl_pct: ((entry_price - exit_price) / entry_price * 100).round(2) }
                 end

    update!(
      status: "closed",
      exit_price: exit_price,
      exit_reason: exit_reason,
      exit_order: exit_order,
      closed_at: Time.current,
      realized_pnl: pnl_result[:pnl],
      realized_pnl_pct: pnl_result[:pnl_pct],
      holding_days: days_held,
      unrealized_pnl: 0,
      unrealized_pnl_pct: 0,
    )
  end

  def mark_as_partially_closed!(exit_quantity:, exit_price:, exit_reason:, exit_order: nil)
    # Calculate P&L for partial exit
    pnl_per_share = if long?
                      exit_price - entry_price
                    else
                      entry_price - exit_price
                    end

    partial_pnl = pnl_per_share * exit_quantity
    remaining_quantity = quantity - exit_quantity

    # Update position
    update!(
      status: remaining_quantity.positive? ? "partially_closed" : "closed",
      quantity: remaining_quantity,
      filled_quantity: filled_quantity + exit_quantity,
      realized_pnl: (realized_pnl || 0) + partial_pnl,
      exit_order: exit_order,
      closed_at: remaining_quantity.zero? ? Time.current : nil,
      exit_reason: exit_reason,
    )

    # Update unrealized P&L for remaining quantity
    update_unrealized_pnl! if remaining_quantity.positive?
  end
end
