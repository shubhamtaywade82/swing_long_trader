# frozen_string_literal: true

namespace :paper_trading do
  desc "Initialize paper trading portfolio with default capital"
  task :init, [:capital] => :environment do |_t, args|
    capital = (args[:capital] || 100_000).to_f
    portfolio = PaperTrading::Portfolio.find_or_create_default(initial_capital: capital)
    puts "Paper trading portfolio initialized: #{portfolio.name} with ₹#{portfolio.capital}"
  end

  desc "Check exit conditions for all open paper positions"
  task check_exits: :environment do
    PaperTrading::ExitMonitorJob.perform_now
  end

  desc "Perform daily mark-to-market reconciliation"
  task reconcile: :environment do
    PaperTrading::ReconciliationJob.perform_now
  end

  desc "Show paper trading portfolio summary"
  task summary: :environment do
    portfolio = PaperTrading::Portfolio.find_or_create_default
    puts "\n📊 Paper Trading Portfolio Summary"
    puts "=" * 50
    puts "Portfolio: #{portfolio.name}"
    puts "Capital: ₹#{portfolio.capital.round(2)}"
    puts "Total Equity: ₹#{portfolio.total_equity.round(2)}"
    puts "Realized P&L: ₹#{portfolio.pnl_realized.round(2)}"
    puts "Unrealized P&L: ₹#{portfolio.pnl_unrealized.round(2)}"
    puts "Total P&L: ₹#{(portfolio.pnl_realized + portfolio.pnl_unrealized).round(2)}"
    puts "Max Drawdown: #{portfolio.max_drawdown.round(2)}%"
    puts "Utilization: #{portfolio.utilization_pct}%"
    puts "Open Positions: #{portfolio.open_positions.count}"
    puts "Closed Positions: #{portfolio.closed_positions.count}"
    puts "Total Exposure: ₹#{portfolio.total_exposure.round(2)}"
    puts "Available Capital: ₹#{portfolio.available_capital.round(2)}"
    puts "=" * 50

    if portfolio.open_positions.any?
      puts "\nOpen Positions:"
      portfolio.open_positions.each do |pos|
        puts "  #{pos.instrument.symbol_name} #{pos.direction.upcase} " \
             "#{pos.quantity} @ ₹#{pos.entry_price} " \
             "(Current: ₹#{pos.current_price}, P&L: ₹#{pos.unrealized_pnl.round(2)})"
      end
    end
  end

  desc "Show paper trading ledger entries"
  task ledger: :environment do |_t, args|
    limit = (args[:limit] || 20).to_i
    portfolio = PaperTrading::Portfolio.find_or_create_default
    entries = portfolio.paper_ledgers.recent.limit(limit)

    puts "\n📝 Recent Ledger Entries (Last #{limit})"
    puts "=" * 80
    entries.each do |entry|
      type_emoji = entry.credit? ? "➕" : "➖"
      puts "#{type_emoji} #{entry.created_at.strftime('%Y-%m-%d %H:%M:%S')} | " \
           "#{entry.transaction_type.upcase} | ₹#{entry.amount.round(2)} | " \
           "#{entry.reason} | #{entry.description}"
    end
    puts "=" * 80
  end
end
