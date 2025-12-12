# frozen_string_literal: true

namespace :positions do
  desc "Sync live positions with DhanHQ"
  task sync_live: :environment do
    puts "Syncing live positions with DhanHQ..."
    result = Positions::Reconciler.reconcile_live

    if result[:success]
      puts "✅ Synced #{result[:positions_updated]} positions"
      if result[:sync_details]
        puts "   Created: #{result[:sync_details][:created_count]}"
        puts "   Updated: #{result[:sync_details][:updated_count]}"
      end
    else
      puts "❌ Sync failed: #{result[:error]}"
    end
  end

  desc "Reconcile paper positions (update prices, P&L)"
  task reconcile_paper: :environment do
    puts "Reconciling paper positions..."
    result = Positions::Reconciler.reconcile_paper

    if result[:success]
      puts "✅ Reconciled #{result[:positions_updated]} positions"
      puts "   Portfolio Equity: ₹#{result[:portfolio_equity]}"
      puts "   Available Capital: ₹#{result[:available_capital]}"
    else
      puts "❌ Reconciliation failed: #{result[:error]}"
    end
  end

  desc "Sync and reconcile all positions (live + paper)"
  task sync_all: :environment do
    puts "Syncing and reconciling all positions..."
    result = Positions::Reconciler.reconcile_all

    puts "\n📊 LIVE POSITIONS:"
    live = result[:live]
    if live[:success]
      puts "   ✅ Synced #{live[:positions_updated]} positions"
      puts "   Created: #{live[:sync_details][:created_count]}" if live[:sync_details]
      puts "   Updated: #{live[:sync_details][:updated_count]}" if live[:sync_details]
    else
      puts "   ❌ Failed: #{live[:error]}"
    end

    puts "\n📘 PAPER POSITIONS:"
    paper = result[:paper]
    if paper[:success]
      puts "   ✅ Reconciled #{paper[:positions_updated]} positions"
      puts "   Portfolio Equity: ₹#{paper[:portfolio_equity]}"
      puts "   Available Capital: ₹#{paper[:available_capital]}"
    else
      puts "   ❌ Failed: #{paper[:error]}"
    end
  end

  desc "List all open positions"
  task list: :environment do
    puts "📊 OPEN POSITIONS"
    puts "=" * 60

    puts "\n🟢 LIVE POSITIONS:"
    live_positions = Position.open.includes(:instrument).recent
    if live_positions.any?
      live_positions.each do |pos|
        puts "  #{pos.symbol} - #{pos.direction.upcase}"
        puts "    Entry: ₹#{pos.entry_price}, Current: ₹#{pos.current_price}"
        puts "    Qty: #{pos.quantity}, P&L: ₹#{pos.unrealized_pnl} (#{pos.unrealized_pnl_pct}%)"
        puts "    Opened: #{pos.opened_at.strftime('%Y-%m-%d')}, Days: #{pos.days_held}"
      end
    else
      puts "  No open live positions"
    end

    puts "\n📘 PAPER POSITIONS:"
    portfolio = PaperTrading::Portfolio.find_or_create_default
    paper_positions = portfolio.open_positions.includes(:instrument).recent
    if paper_positions.any?
      paper_positions.each do |pos|
        puts "  #{pos.instrument.symbol_name} - #{pos.direction.upcase}"
        puts "    Entry: ₹#{pos.entry_price}, Current: ₹#{pos.current_price}"
        puts "    Qty: #{pos.quantity}, P&L: ₹#{pos.unrealized_pnl} (#{pos.unrealized_pnl_pct}%)"
        puts "    Opened: #{pos.opened_at.strftime('%Y-%m-%d')}, Days: #{pos.days_held}"
      end
    else
      puts "  No open paper positions"
    end
  end

  desc "Show position summary"
  task summary: :environment do
    puts "📊 POSITION SUMMARY"
    puts "=" * 60

    live_open = Position.open.count
    live_closed = Position.closed.count
    paper_open = PaperPosition.open.count
    paper_closed = PaperPosition.closed.count

    puts "\n🟢 LIVE TRADING:"
    puts "   Open: #{live_open}"
    puts "   Closed: #{live_closed}"
    puts "   Total: #{live_open + live_closed}"

    if live_open.positive?
      total_unrealized = Position.open.sum(:unrealized_pnl)
      puts "   Unrealized P&L: ₹#{total_unrealized.round(2)}"
    end

    puts "\n📘 PAPER TRADING:"
    puts "   Open: #{paper_open}"
    puts "   Closed: #{paper_closed}"
    puts "   Total: #{paper_open + paper_closed}"

    if paper_open.positive?
      portfolio = PaperTrading::Portfolio.find_or_create_default
      puts "   Unrealized P&L: ₹#{portfolio.pnl_unrealized.round(2)}"
      puts "   Realized P&L: ₹#{portfolio.pnl_realized.round(2)}"
      puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
    end
  end
end
