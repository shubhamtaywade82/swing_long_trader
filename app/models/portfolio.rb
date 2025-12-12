# frozen_string_literal: true

# Portfolio uses Single Table Inheritance (STI) from Position
# Portfolio aggregates positions that continue from previous day
class Portfolio < Position
  self.table_name = "positions"

  validates :portfolio_type, :portfolio_date, presence: true
  validates :portfolio_type, inclusion: { in: %w[live paper] }
  validates :portfolio_date, uniqueness: { scope: :portfolio_type }

  scope :live, -> { where(portfolio_type: "live") }
  scope :paper, -> { where(portfolio_type: "paper") }
  scope :recent, -> { order(portfolio_date: :desc) }
  scope :by_date, ->(date) { where(portfolio_date: date) }
  scope :by_type, ->(type) { where(portfolio_type: type) }

  # Get all positions that belong to this portfolio snapshot
  # For live: positions are in same table (STI)
  # For paper: positions are in separate PaperPosition table
  def positions
    if live?
      Position.regular_positions
              .where(portfolio_date: portfolio_date)
              .where("(portfolio_type = ? OR (portfolio_type IS NULL AND portfolio_date = ?))", portfolio_type, portfolio_date)
    else
      # For paper, query PaperPosition table
      portfolio = PaperTrading::Portfolio.find_or_create_default
      PaperPosition.where(portfolio_id: portfolio.id)
                   .where("opened_at::date <= ? AND (closed_at IS NULL OR closed_at::date >= ?)", portfolio_date, portfolio_date)
    end
  end

  # Get positions that continued from previous day
  def continued_positions
    if live?
      positions.where(continued_from_previous_day: true)
    else
      # For paper, check metadata
      positions.select do |pos|
        pos.metadata_hash["continued_from_previous_day"] == true
      end
    end
  end

  # Get new positions opened on this date
  def new_positions
    if live?
      positions.where(continued_from_previous_day: false)
              .where("opened_at::date = ?", portfolio_date)
    else
      # For paper, check metadata
      positions.select do |pos|
        pos.metadata_hash["continued_from_previous_day"] != true &&
          pos.opened_at.to_date == portfolio_date
      end
    end
  end

  # Get positions closed on this date
  def closed_positions_today
    positions.where(status: "closed")
            .where("closed_at::date = ?", portfolio_date)
  end

  # Get open positions at end of day
  def open_positions_at_eod
    positions.where(status: "open")
            .where("opened_at::date <= ?", portfolio_date)
  end

  def live?
    portfolio_type == "live"
  end

  def paper?
    portfolio_type == "paper"
  end

  def self.create_from_positions(date:, portfolio_type: "live")
    date = date.is_a?(Date) ? date : Date.parse(date.to_s)

    # Check if portfolio already exists
    existing = find_by(portfolio_type: portfolio_type, portfolio_date: date)
    return existing if existing

    # Get positions for this date
    positions_data = get_positions_for_date(date, portfolio_type)

    # Mark positions that continue from previous day
    mark_continued_positions(date, portfolio_type, positions_data)

    # Calculate portfolio metrics
    metrics = calculate_portfolio_metrics(positions_data, date, portfolio_type)

    # Create portfolio record (STI)
    portfolio = create!(
      type: "Portfolio",
      portfolio_type: portfolio_type,
      portfolio_date: date,
      symbol: portfolio_type == "live" ? "LIVE_PORTFOLIO" : "PAPER_PORTFOLIO",
      direction: "long", # Dummy value for STI
      entry_price: 0, # Dummy value
      current_price: 0, # Dummy value
      quantity: 0, # Dummy value
      status: "open", # Portfolio is always "open"
      opened_at: date.beginning_of_day,
      opening_capital: metrics[:opening_capital],
      closing_capital: metrics[:closing_capital],
      total_equity: metrics[:total_equity],
      available_capital: metrics[:available_capital],
      total_exposure: metrics[:total_exposure],
      open_positions_count: metrics[:open_positions_count],
      closed_positions_count: metrics[:closed_positions_count],
      utilization_pct: metrics[:utilization_pct],
      win_rate: metrics[:win_rate],
      peak_equity: metrics[:peak_equity],
      unrealized_pnl: metrics[:unrealized_pnl],
      realized_pnl: metrics[:realized_pnl],
      metadata: {
        calculated_at: Time.current,
        positions_summary: positions_data[:summary],
      }.to_json,
    )

    # Update positions with portfolio_date
    update_positions_with_portfolio_date(positions_data, date, portfolio_type)

    portfolio
  end

  def self.get_positions_for_date(date, portfolio_type)
    if portfolio_type == "live"
      # Get live positions
      open_positions = Position.regular_positions
                              .where(portfolio_type: "live")
                              .or(Position.regular_positions.where(portfolio_type: nil)) # Legacy positions
                              .open
                              .where("opened_at::date <= ?", date)
                              .includes(:instrument)

      closed_today = Position.regular_positions
                             .where(portfolio_type: "live")
                             .or(Position.regular_positions.where(portfolio_type: nil))
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
      open_positions = PaperPosition
                       .where(portfolio_id: portfolio.id)
                       .open
                       .where("opened_at::date <= ?", date)
                       .includes(:instrument)

      closed_today = PaperPosition
                     .where(portfolio_id: portfolio.id)
                     .closed
                     .where("closed_at::date = ?", date)
                     .includes(:instrument)

      {
        open: open_positions,
        closed_today: closed_today,
        summary: build_paper_positions_summary(open_positions, closed_today, portfolio),
      }
    end
  end

  def self.mark_continued_positions(date, portfolio_type, positions_data)
    previous_date = date - 1.day

    # Get previous day's portfolio
    previous_portfolio = find_by(portfolio_type: portfolio_type, portfolio_date: previous_date)

    return unless previous_portfolio

    # Get positions that were open yesterday
    previous_open = previous_portfolio.open_positions_at_eod

    if portfolio_type == "live"
      # For live positions, mark continued_from_previous_day column
      previous_symbols = previous_open.map { |p| "#{p.symbol}_#{p.direction}" }.to_set

      positions_data[:open].each do |pos|
        if previous_symbols.include?("#{pos.symbol}_#{pos.direction}")
          pos.update_column(:continued_from_previous_day, true) if pos.respond_to?(:continued_from_previous_day)
        end
      end
    else
      # For paper positions, we track continuation in metadata since PaperPosition doesn't have this column
      previous_symbols = previous_open.map { |p| "#{p.instrument.symbol_name}_#{p.direction}" }.to_set

      positions_data[:open].each do |pos|
        if previous_symbols.include?("#{pos.instrument.symbol_name}_#{pos.direction}")
          metadata = pos.metadata_hash
          metadata["continued_from_previous_day"] = true
          pos.update_column(:metadata, metadata.to_json)
        end
      end
    end
  end

  def self.update_positions_with_portfolio_date(positions_data, date, portfolio_type)
    # Update all positions with portfolio_date
    all_positions = positions_data[:open] + positions_data[:closed_today]

    all_positions.each do |pos|
      if portfolio_type == "live" && pos.respond_to?(:portfolio_date)
        # Live positions: update portfolio_date column
        pos.update_columns(
          portfolio_date: date,
          portfolio_type: portfolio_type,
        )
      elsif portfolio_type == "paper"
        # Paper positions: store portfolio_date in metadata
        metadata = pos.metadata_hash
        metadata["portfolio_date"] = date.to_s
        metadata["portfolio_type"] = portfolio_type
        pos.update_column(:metadata, metadata.to_json)
      end
    end
  end

  def self.calculate_portfolio_metrics(positions_data, date, portfolio_type)
    open_positions = positions_data[:open]
    closed_today = positions_data[:closed_today]

    # Get previous day's portfolio for opening capital
    previous_date = date - 1.day
    previous_portfolio = find_by(portfolio_type: portfolio_type, portfolio_date: previous_date)

    opening_capital = if previous_portfolio
                       previous_portfolio.closing_capital || previous_portfolio.total_equity
                     elsif portfolio_type == "paper"
                       PaperTrading::Portfolio.find_or_create_default.capital
                     else
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
                        total_equity - total_exposure
                      end

    # Calculate win rate from closed positions
    winners = closed_today.count { |pos| (pos.realized_pnl || 0).positive? }
    win_rate = closed_today.any? ? (winners.to_f / closed_today.count * 100).round(2) : 0

    # Calculate utilization
    utilization_pct = total_equity.positive? ? (total_exposure / total_equity * 100).round(2) : 0

    # Get peak equity (would need historical tracking)
    peak_equity = total_equity

    {
      opening_capital: opening_capital.round(2),
      closing_capital: closing_capital.round(2),
      total_equity: total_equity.round(2),
      available_capital: available_capital.round(2),
      realized_pnl: realized_pnl.round(2),
      unrealized_pnl: unrealized_pnl.round(2),
      open_positions_count: open_positions.count,
      closed_positions_count: closed_today.count,
      total_exposure: total_exposure.round(2),
      utilization_pct: utilization_pct,
      peak_equity: peak_equity.round(2),
      win_rate: win_rate,
    }
  end

  def self.build_positions_summary(open_positions, closed_positions)
    {
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
          continued: pos.continued_from_previous_day,
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
  end

  def self.build_paper_positions_summary(open_positions, closed_positions, portfolio)
    {
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
  end
end
