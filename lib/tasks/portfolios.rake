# frozen_string_literal: true

namespace :portfolios do
  desc "Initialize paper trading portfolio with capital"
  task initialize_paper: :environment do
    puts "Initializing paper trading portfolio..."

    result = Portfolios::PaperPortfolioInitializer.call

    if result[:success]
      portfolio = result[:portfolio]
      puts "✅ Paper portfolio initialized successfully!"
      puts "   Portfolio ID: #{portfolio.id}"
      puts "   Name: #{portfolio.name}"
      puts "   Mode: #{portfolio.mode}"
      puts "   Total Equity: ₹#{portfolio.total_equity}"
      puts "   Swing Capital: ₹#{portfolio.swing_capital}"
      puts "   Available Swing Capital: ₹#{portfolio.available_swing_capital}"
      puts "   Long-term Capital: ₹#{portfolio.long_term_capital}"
      puts "   Available Cash: ₹#{portfolio.available_cash}"
    else
      puts "❌ Failed to initialize paper portfolio: #{result[:error]}"
      exit 1
    end
  end

  desc "Rebalance paper portfolio capital allocation"
  task rebalance_paper: :environment do
    portfolio = CapitalAllocationPortfolio.paper.active.first

    unless portfolio
      puts "❌ No paper portfolio found. Run 'rake portfolios:initialize_paper' first."
      exit 1
    end

    puts "Rebalancing paper portfolio capital..."
    puts "   Before: swing_capital=₹#{portfolio.swing_capital}, available=₹#{portfolio.available_swing_capital}"

    portfolio.rebalance_capital!
    portfolio.reload

    puts "✅ Portfolio rebalanced!"
    puts "   After: swing_capital=₹#{portfolio.swing_capital}, available=₹#{portfolio.available_swing_capital}"
  end

  desc "Show paper portfolio status"
  task status: :environment do
    portfolio = CapitalAllocationPortfolio.paper.active.first

    unless portfolio
      puts "❌ No paper portfolio found."
      exit 1
    end

    puts "Paper Portfolio Status:"
    puts "=" * 50
    puts "ID: #{portfolio.id}"
    puts "Name: #{portfolio.name}"
    puts "Mode: #{portfolio.mode}"
    puts "Total Equity: ₹#{portfolio.total_equity}"
    puts "Swing Capital: ₹#{portfolio.swing_capital}"
    puts "Available Swing Capital: ₹#{portfolio.available_swing_capital}"
    puts "Long-term Capital: ₹#{portfolio.long_term_capital}"
    puts "Available Cash: ₹#{portfolio.available_cash}"
    puts "Open Positions: #{portfolio.open_swing_positions.count}"
    puts "Total Swing Exposure: ₹#{portfolio.total_swing_exposure}"
    puts "Realized P&L: ₹#{portfolio.realized_pnl}"
    puts "Unrealized P&L: ₹#{portfolio.unrealized_pnl}"
    puts "Max Drawdown: #{portfolio.max_drawdown}%"
    puts "=" * 50
  end
end
