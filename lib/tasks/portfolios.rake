# frozen_string_literal: true

namespace :portfolios do
  desc "Create daily portfolio snapshot for today"
  task snapshot: :environment do
    date = Time.zone.today
    puts "Creating portfolio snapshot for #{date}..."

    result = Portfolios::DailySnapshot.create_for_date(date: date, portfolio_type: "all")

    if result[:live] && result[:live][:success]
      live = result[:live][:portfolio]
      puts "\n🟢 LIVE PORTFOLIO:"
      puts "   Date: #{live.date}"
      puts "   Opening Capital: ₹#{live.opening_capital}"
      puts "   Closing Capital: ₹#{live.closing_capital}"
      puts "   Total Equity: ₹#{live.total_equity}"
      puts "   Realized P&L: ₹#{live.realized_pnl}"
      puts "   Unrealized P&L: ₹#{live.unrealized_pnl}"
      puts "   Open Positions: #{live.open_positions_count}"
      puts "   Closed Today: #{live.closed_positions_count}"
    end

    if result[:paper] && result[:paper][:success]
      paper = result[:paper][:portfolio]
      puts "\n📘 PAPER PORTFOLIO:"
      puts "   Date: #{paper.date}"
      puts "   Opening Capital: ₹#{paper.opening_capital}"
      puts "   Closing Capital: ₹#{paper.closing_capital}"
      puts "   Total Equity: ₹#{paper.total_equity}"
      puts "   Realized P&L: ₹#{paper.realized_pnl}"
      puts "   Unrealized P&L: ₹#{paper.unrealized_pnl}"
      puts "   Open Positions: #{paper.open_positions_count}"
      puts "   Closed Today: #{paper.closed_positions_count}"
    end
  end

  desc "Create portfolio snapshot for specific date"
  task :snapshot_date, [:date] => :environment do |_t, args|
    date_str = args[:date] || Time.zone.today.to_s
    date = Date.parse(date_str)
    puts "Creating portfolio snapshot for #{date}..."

    result = Portfolios::DailySnapshot.create_for_date(date: date, portfolio_type: "all")

    if result[:live] && result[:live][:success]
      puts "✅ Live portfolio snapshot created"
    elsif result[:live]
      puts "❌ Live portfolio failed: #{result[:live][:error]}"
    end

    if result[:paper] && result[:paper][:success]
      puts "✅ Paper portfolio snapshot created"
    elsif result[:paper]
      puts "❌ Paper portfolio failed: #{result[:paper][:error]}"
    end
  end

  desc "Show portfolio for today"
  task show: :environment do
    date = Time.zone.today
    show_portfolio(date)
  end

  desc "Show portfolio for specific date"
  task :show_date, [:date] => :environment do |_t, args|
    date_str = args[:date] || Time.zone.today.to_s
    date = Date.parse(date_str)
    show_portfolio(date)
  end

  desc "List all portfolio snapshots"
  task list: :environment do
    puts "📊 PORTFOLIO SNAPSHOTS"
    puts "=" * 60

    live_portfolios = Portfolio.live.recent.limit(10)
    paper_portfolios = Portfolio.paper.recent.limit(10)

    puts "\n🟢 LIVE PORTFOLIOS:"
    if live_portfolios.any?
      live_portfolios.each do |p|
        puts "  #{p.date} - Equity: ₹#{p.total_equity}, P&L: ₹#{p.total_pnl} (#{p.pnl_pct}%)"
        puts "    Open: #{p.open_positions_count}, Closed: #{p.closed_positions_count}"
      end
    else
      puts "  No live portfolios found"
    end

    puts "\n📘 PAPER PORTFOLIOS:"
    if paper_portfolios.any?
      paper_portfolios.each do |p|
        puts "  #{p.date} - Equity: ₹#{p.total_equity}, P&L: ₹#{p.total_pnl} (#{p.pnl_pct}%)"
        puts "    Open: #{p.open_positions_count}, Closed: #{p.closed_positions_count}"
      end
    else
      puts "  No paper portfolios found"
    end
  end

  def show_portfolio(date)
    puts "📊 PORTFOLIO SNAPSHOT - #{date}"
    puts "=" * 60

    live = Portfolio.find_by(portfolio_type: "live", date: date)
    paper = Portfolio.find_by(portfolio_type: "paper", date: date)

    if live
      puts "\n🟢 LIVE PORTFOLIO:"
      puts "   Opening Capital: ₹#{live.opening_capital}"
      puts "   Closing Capital: ₹#{live.closing_capital}"
      puts "   Total Equity: ₹#{live.total_equity}"
      puts "   Available Capital: ₹#{live.available_capital}"
      puts "   Realized P&L: ₹#{live.realized_pnl}"
      puts "   Unrealized P&L: ₹#{live.unrealized_pnl}"
      puts "   Total P&L: ₹#{live.total_pnl} (#{live.pnl_pct}%)"
      puts "   Open Positions: #{live.open_positions_count}"
      puts "   Closed Today: #{live.closed_positions_count}"
      puts "   Total Exposure: ₹#{live.total_exposure}"
      puts "   Utilization: #{live.utilization_pct}%"
      puts "   Win Rate: #{live.win_rate}%"

      # Show continued positions
      continued = live.continued_positions
      if continued.any?
        puts "\n   📌 Continued Positions (#{continued.size}):"
        continued.each do |pos|
          puts "      #{pos['symbol']} #{pos['direction'].upcase} - Entry: ₹#{pos['entry_price']}, Current: ₹#{pos['current_price']}, P&L: ₹#{pos['unrealized_pnl']}"
        end
      end

      # Show new positions
      new_pos = live.new_positions_today
      if new_pos.any?
        puts "\n   🆕 New Positions Today (#{new_pos.size}):"
        new_pos.each do |pos|
          puts "      #{pos['symbol']} #{pos['direction'].upcase} - Entry: ₹#{pos['entry_price']}, Current: ₹#{pos['current_price']}"
        end
      end
    else
      puts "\n🟢 LIVE PORTFOLIO: Not found for #{date}"
      puts "   Run: rails portfolios:snapshot_date[#{date}]"
    end

    if paper
      puts "\n📘 PAPER PORTFOLIO:"
      puts "   Opening Capital: ₹#{paper.opening_capital}"
      puts "   Closing Capital: ₹#{paper.closing_capital}"
      puts "   Total Equity: ₹#{paper.total_equity}"
      puts "   Available Capital: ₹#{paper.available_capital}"
      puts "   Realized P&L: ₹#{paper.realized_pnl}"
      puts "   Unrealized P&L: ₹#{paper.unrealized_pnl}"
      puts "   Total P&L: ₹#{paper.total_pnl} (#{paper.pnl_pct}%)"
      puts "   Open Positions: #{paper.open_positions_count}"
      puts "   Closed Today: #{paper.closed_positions_count}"
      puts "   Total Exposure: ₹#{paper.total_exposure}"
      puts "   Utilization: #{paper.utilization_pct}%"
      puts "   Win Rate: #{paper.win_rate}%"

      # Show continued positions
      continued = paper.continued_positions
      if continued.any?
        puts "\n   📌 Continued Positions (#{continued.size}):"
        continued.each do |pos|
          puts "      #{pos['symbol']} #{pos['direction'].upcase} - Entry: ₹#{pos['entry_price']}, Current: ₹#{pos['current_price']}, P&L: ₹#{pos['unrealized_pnl']}"
        end
      end

      # Show new positions
      new_pos = paper.new_positions_today
      if new_pos.any?
        puts "\n   🆕 New Positions Today (#{new_pos.size}):"
        new_pos.each do |pos|
          puts "      #{pos['symbol']} #{pos['direction'].upcase} - Entry: ₹#{pos['entry_price']}, Current: ₹#{pos['current_price']}"
        end
      end
    else
      puts "\n📘 PAPER PORTFOLIO: Not found for #{date}"
      puts "   Run: rails portfolios:snapshot_date[#{date}]"
    end
  end
end
