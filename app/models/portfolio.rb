# frozen_string_literal: true

class Portfolio < ApplicationRecord
  validates :name, :portfolio_type, :date, :opening_capital, :total_equity, presence: true
  validates :portfolio_type, inclusion: { in: %w[live paper] }
  validates :date, uniqueness: { scope: :portfolio_type }

  scope :live, -> { where(portfolio_type: "live") }
  scope :paper, -> { where(portfolio_type: "paper") }
  scope :recent, -> { order(date: :desc) }
  scope :by_date, ->(date) { where(date: date) }
  scope :by_type, ->(type) { where(portfolio_type: type) }

  def metadata_hash
    return {} if metadata.blank?

    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def positions_summary_hash
    return [] if positions_summary.blank?

    JSON.parse(positions_summary)
  rescue JSON::ParserError
    []
  end

  def live?
    portfolio_type == "live"
  end

  def paper?
    portfolio_type == "paper"
  end

  def self.create_from_positions(date:, portfolio_type: "live", name: nil)
    name ||= portfolio_type == "live" ? "live_portfolio" : "paper_portfolio"

    # Get positions for this date
    positions_data = get_positions_for_date(date, portfolio_type)

    # Calculate portfolio metrics
    metrics = calculate_portfolio_metrics(positions_data, date, portfolio_type)

    # Create portfolio record
    create!(
      name: name,
      portfolio_type: portfolio_type,
      date: date,
      opening_capital: metrics[:opening_capital],
      closing_capital: metrics[:closing_capital],
      total_equity: metrics[:total_equity],
      available_capital: metrics[:available_capital],
      realized_pnl: metrics[:realized_pnl],
      unrealized_pnl: metrics[:unrealized_pnl],
      total_pnl: metrics[:total_pnl],
      pnl_pct: metrics[:pnl_pct],
      open_positions_count: metrics[:open_positions_count],
      closed_positions_count: metrics[:closed_positions_count],
      total_positions_count: metrics[:total_positions_count],
      total_exposure: metrics[:total_exposure],
      utilization_pct: metrics[:utilization_pct],
      max_drawdown: metrics[:max_drawdown],
      peak_equity: metrics[:peak_equity],
      win_rate: metrics[:win_rate],
      avg_win: metrics[:avg_win],
      avg_loss: metrics[:avg_loss],
      positions_summary: positions_data[:summary].to_json,
      metadata: {
        calculated_at: Time.current,
        positions_data: positions_data,
      }.to_json,
    )
  end

  def self.get_positions_for_date(date, portfolio_type)
    if portfolio_type == "live"
      # Get live positions
      # Open positions: positions that were open at end of previous day or opened today
      # Closed positions: positions closed today
      open_positions = Position
                       .open
                       .where("opened_at::date <= ?", date)
                       .includes(:instrument)

      closed_today = Position
                     .closed
                     .where("closed_at::date = ?", date)
                     .includes(:instrument)

      {
        open: open_positions,
        closed_today: closed_today,
        summary: build_positions_summary(open_positions, closed_today),
      }
    else
      # Get paper positions
      portfolio = PaperTrading::Portfolio.find_or_create_default
      open_positions = portfolio
                       .open_positions
                       .where("opened_at::date <= ?", date)
                       .includes(:instrument)

      closed_today = portfolio
                     .closed_positions
                     .where("closed_at::date = ?", date)
                     .includes(:instrument)

      {
        open: open_positions,
        closed_today: closed_today,
        summary: build_paper_positions_summary(open_positions, closed_today, portfolio),
      }
    end
  end

  def self.calculate_portfolio_metrics(positions_data, date, portfolio_type)
    open_positions = positions_data[:open]
    closed_today = positions_data[:closed_today]

    # Get previous day's portfolio for opening capital
    previous_portfolio = Portfolio
                        .where(portfolio_type: portfolio_type)
                        .where("date < ?", date)
                        .order(date: :desc)
                        .first

    opening_capital = if previous_portfolio
                       previous_portfolio.closing_capital || previous_portfolio.total_equity
                     elsif portfolio_type == "paper"
                       PaperTrading::Portfolio.find_or_create_default.capital
                     else
                       # For live, would need to get from DhanHQ or settings
                       Setting.fetch_i("portfolio.current_capital", 100_000)
                     end

    # Calculate realized P&L from closed positions today
    realized_pnl = closed_today.sum do |pos|
      portfolio_type == "live" ? (pos.realized_pnl || 0) : (pos.realized_pnl || 0)
    end

    # Calculate unrealized P&L from open positions
    unrealized_pnl = open_positions.sum do |pos|
      portfolio_type == "live" ? (pos.unrealized_pnl || 0) : (pos.unrealized_pnl || 0)
    end

    # Calculate total exposure
    total_exposure = open_positions.sum do |pos|
      portfolio_type == "live" ? (pos.current_price * pos.quantity) : (pos.current_price * pos.quantity)
    end

    # Calculate closing capital
    closing_capital = opening_capital + realized_pnl

    # Calculate total equity
    total_equity = closing_capital + unrealized_pnl

    # Calculate available capital
    available_capital = if portfolio_type == "paper"
                         portfolio = PaperTrading::Portfolio.find_or_create_default
                         portfolio.available_capital
                       else
                         # For live, would check DhanHQ balance
                         total_equity - total_exposure
                       end

    # Calculate P&L percentage
    pnl_pct = opening_capital.positive? ? ((total_equity - opening_capital) / opening_capital * 100).round(2) : 0

    # Calculate win rate from closed positions
    winners = closed_today.count { |pos| (pos.realized_pnl || 0).positive? }
    win_rate = closed_today.any? ? (winners.to_f / closed_today.count * 100).round(2) : 0

    # Calculate average win/loss
    wins = closed_today.select { |pos| (pos.realized_pnl || 0).positive? }.map { |pos| pos.realized_pnl || 0 }
    losses = closed_today.select { |pos| (pos.realized_pnl || 0).negative? }.map { |pos| pos.realized_pnl || 0 }
    avg_win = wins.any? ? (wins.sum / wins.count).round(2) : 0
    avg_loss = losses.any? ? (losses.sum / losses.count).round(2) : 0

    # Calculate utilization
    utilization_pct = total_equity.positive? ? (total_exposure / total_equity * 100).round(2) : 0

    # Get peak equity (would need historical tracking)
    peak_equity = total_equity # Simplified - would track historically
    max_drawdown = peak_equity.positive? ? (((peak_equity - total_equity) / peak_equity) * 100).round(2) : 0

    {
      opening_capital: opening_capital.round(2),
      closing_capital: closing_capital.round(2),
      total_equity: total_equity.round(2),
      available_capital: available_capital.round(2),
      realized_pnl: realized_pnl.round(2),
      unrealized_pnl: unrealized_pnl.round(2),
      total_pnl: (realized_pnl + unrealized_pnl).round(2),
      pnl_pct: pnl_pct,
      open_positions_count: open_positions.count,
      closed_positions_count: closed_today.count,
      total_positions_count: open_positions.count + closed_today.count,
      total_exposure: total_exposure.round(2),
      utilization_pct: utilization_pct,
      max_drawdown: max_drawdown,
      peak_equity: peak_equity.round(2),
      win_rate: win_rate,
      avg_win: avg_win,
      avg_loss: avg_loss,
    }
  end

  def self.build_positions_summary(open_positions, closed_positions)
    summary = {
      open: open_positions.map do |pos|
        {
          id: pos.id,
          symbol: pos.symbol,
          direction: pos.direction,
          entry_price: pos.entry_price,
          current_price: pos.current_price,
          quantity: pos.quantity,
          unrealized_pnl: pos.unrealized_pnl,
          unrealized_pnl_pct: pos.unrealized_pnl_pct,
          opened_at: pos.opened_at,
          days_held: pos.days_held,
        }
      end,
      closed_today: closed_positions.map do |pos|
        {
          id: pos.id,
          symbol: pos.symbol,
          direction: pos.direction,
          entry_price: pos.entry_price,
          exit_price: pos.exit_price,
          quantity: pos.quantity,
          realized_pnl: pos.realized_pnl,
          realized_pnl_pct: pos.realized_pnl_pct,
          exit_reason: pos.exit_reason,
          holding_days: pos.holding_days,
        }
      end,
    }

    summary
  end

  def self.build_paper_positions_summary(open_positions, closed_positions, portfolio)
    summary = {
      open: open_positions.map do |pos|
        {
          id: pos.id,
          symbol: pos.instrument.symbol_name,
          direction: pos.direction,
          entry_price: pos.entry_price,
          current_price: pos.current_price,
          quantity: pos.quantity,
          unrealized_pnl: pos.unrealized_pnl,
          unrealized_pnl_pct: pos.unrealized_pnl_pct,
          opened_at: pos.opened_at,
          days_held: pos.days_held,
        }
      end,
      closed_today: closed_positions.map do |pos|
        {
          id: pos.id,
          symbol: pos.instrument.symbol_name,
          direction: pos.direction,
          entry_price: pos.entry_price,
          exit_price: pos.exit_price,
          quantity: pos.quantity,
          realized_pnl: pos.realized_pnl,
          realized_pnl_pct: pos.realized_pnl_pct,
          exit_reason: pos.exit_reason,
          holding_days: pos.holding_days,
        }
      end,
      portfolio_name: portfolio.name,
    }

    summary
  end

  # Get positions that continue from previous day
  def continued_positions
    previous_date = date - 1.day
    previous_portfolio = Portfolio.find_by(portfolio_type: portfolio_type, date: previous_date)

    return [] unless previous_portfolio

    previous_open = previous_portfolio.positions_summary_hash["open"] || []
    current_open = positions_summary_hash["open"] || []

    # Find positions that were open yesterday and still open today
    continued = []
    current_open.each do |current_pos|
      previous_pos = previous_open.find { |p| p["symbol"] == current_pos["symbol"] && p["direction"] == current_pos["direction"] }
      continued << current_pos if previous_pos
    end

    continued
  end

  # Get new positions opened today
  def new_positions_today
    previous_date = date - 1.day
    previous_portfolio = Portfolio.find_by(portfolio_type: portfolio_type, date: previous_date)

    current_open = positions_summary_hash["open"] || []

    if previous_portfolio
      previous_open = previous_portfolio.positions_summary_hash["open"] || []
      previous_symbols = previous_open.map { |p| "#{p['symbol']}_#{p['direction']}" }.to_set

      current_open.reject do |pos|
        previous_symbols.include?("#{pos['symbol']}_#{pos['direction']}")
      end
    else
      current_open
    end
  end
end
