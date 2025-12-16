# frozen_string_literal: true

namespace :test do
  namespace :capital do
    desc "Test Capital Allocation Portfolio creation"
    task :portfolio, [:name, :mode, :initial_capital] => :environment do |_t, args|
      name = args[:name] || "Test Portfolio"
      mode = args[:mode] || "paper"
      initial_capital = (args[:initial_capital] || 100_000).to_f

      puts "\n💰 Testing Capital Allocation Portfolio\n"
      puts "=" * 80

      portfolio = CapitalAllocationPortfolio.find_or_create_by(name: name) do |p|
        p.mode = mode
        p.total_equity = initial_capital
        p.available_cash = initial_capital
        p.swing_capital = 0
        p.long_term_capital = 0
        p.peak_equity = initial_capital
      end

      # Rebalance capital
      PortfolioServices::CapitalBucketer.new(portfolio: portfolio).call

      puts "✅ Portfolio created/updated: #{portfolio.name}"
      puts "\n📊 Portfolio Details:"
      puts "   Mode: #{portfolio.mode}"
      puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
      puts "   Swing Capital: ₹#{portfolio.swing_capital.round(2)}"
      puts "   Long-Term Capital: ₹#{portfolio.long_term_capital.round(2)}"
      puts "   Available Cash: ₹#{portfolio.available_cash.round(2)}"

      bucket = portfolio.capital_bucket
      if bucket
        puts "\n📈 Capital Allocation:"
        puts "   Swing: #{bucket.swing_pct}%"
        puts "   Long-Term: #{bucket.long_term_pct}%"
        puts "   Cash: #{bucket.cash_pct}%"
        puts "   Phase: #{bucket.phase}"
      end

      risk_config = portfolio.swing_risk_config
      if risk_config
        puts "\n⚠️  Risk Configuration:"
        puts "   Risk per Trade: #{risk_config.risk_per_trade}%"
        puts "   Max Position Exposure: #{risk_config.max_position_exposure}%"
        puts "   Max Open Positions: #{risk_config.max_open_positions}"
        puts "   Max Daily Risk: #{risk_config.max_daily_risk}%"
        puts "   Max Portfolio DD: #{risk_config.max_portfolio_dd}%"
      end

      puts "\n✅ Test completed successfully!"
    end

    desc "Test Position Sizing"
    task :position_size, [:symbol, :entry, :sl] => :environment do |_t, args|
      symbol = args[:symbol] || "RELIANCE"
      entry_price = args[:entry]&.to_f || 2500.0
      stop_loss = args[:sl]&.to_f || 2400.0

      puts "\n📏 Testing Position Sizing\n"
      puts "=" * 80

      portfolio = CapitalAllocationPortfolio.find_or_create_by(name: "Test Portfolio") do |p|
        p.mode = "paper"
        p.total_equity = 500_000
        p.available_cash = 500_000
        p.swing_capital = 400_000
        p.long_term_capital = 0
        p.peak_equity = 500_000
      end

      PortfolioServices::CapitalBucketer.new(portfolio: portfolio).call

      instrument = Instrument.find_by(symbol_name: symbol.upcase)
      unless instrument
        puts "❌ Instrument not found: #{symbol}"
        exit 1
      end

      puts "📊 Portfolio: #{portfolio.name}"
      puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
      puts "   Available Swing Capital: ₹#{portfolio.available_swing_capital.round(2)}"
      puts "\n📈 Trade Setup:"
      puts "   Symbol: #{symbol}"
      puts "   Entry Price: ₹#{entry_price}"
      puts "   Stop Loss: ₹#{stop_loss}"

      result = Swing::PositionSizer.call(
        portfolio: portfolio,
        entry_price: entry_price,
        stop_loss: stop_loss,
        instrument: instrument,
      )

      if result[:success]
        puts "\n✅ Position Sizing successful!\n"
        puts "📊 Results:"
        puts "   Quantity: #{result[:quantity]} shares"
        puts "   Capital Required: ₹#{result[:capital_required].round(2)}"
        puts "   Risk Amount: ₹#{result[:risk_amount].round(2)}"
        puts "   Risk Percentage: #{result[:risk_percentage]}%"
        puts "   Risk per Share: ₹#{result[:risk_per_share].round(2)}"

        risk_config = portfolio.swing_risk_config
        puts "\n⚠️  Risk Limits:"
        puts "   Max Risk per Trade: ₹#{risk_config.risk_per_trade_amount.round(2)}"
        puts "   Max Position Exposure: ₹#{risk_config.max_position_exposure_amount.round(2)}"
        puts "   Actual Risk: #{result[:risk_percentage]}% (Limit: #{risk_config.risk_per_trade}%)"
        puts "   Actual Exposure: #{(result[:capital_required] / portfolio.total_equity * 100).round(2)}% (Limit: #{risk_config.max_position_exposure}%)"

        puts "\n✅ Test completed successfully!"
      else
        puts "❌ Position sizing failed: #{result[:error]}"
        exit 1
      end
    end

    desc "Test Risk Manager"
    task :risk_manager, [:portfolio_name] => :environment do |_t, args|
      portfolio_name = args[:portfolio_name] || "Test Portfolio"

      puts "\n⚠️  Testing Risk Manager\n"
      puts "=" * 80

      portfolio = CapitalAllocationPortfolio.find_by(name: portfolio_name)
      unless portfolio
        puts "❌ Portfolio not found: #{portfolio_name}"
        puts "💡 Create it first with: rake test:capital:portfolio"
        exit 1
      end

      puts "📊 Portfolio: #{portfolio.name}"
      puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
      puts "   Max Drawdown: #{portfolio.max_drawdown}%"
      puts "   Open Positions: #{portfolio.open_swing_positions.count}"

      risk_manager = PortfolioServices::RiskManager.new(portfolio: portfolio)
      result = risk_manager.call

      puts "\n🔍 Risk Checks:\n"
      result[:checks].each do |check_name, passed|
        status = passed ? "✅ PASS" : "❌ FAIL"
        puts "   #{check_name.to_s.humanize}: #{status}"
      end

      if result[:allowed]
        puts "\n✅ All checks passed - New positions allowed"
      else
        puts "\n❌ Some checks failed - New positions BLOCKED"
        puts "   Reasons: #{result[:reasons].join(', ')}"
      end

      puts "\n✅ Test completed successfully!"
    end

    desc "Test Capital Rebalancing"
    task :rebalance, [:portfolio_name, :new_equity] => :environment do |_t, args|
      portfolio_name = args[:portfolio_name] || "Test Portfolio"
      new_equity = args[:new_equity]&.to_f

      puts "\n🔄 Testing Capital Rebalancing\n"
      puts "=" * 80

      portfolio = CapitalAllocationPortfolio.find_by(name: portfolio_name)
      unless portfolio
        puts "❌ Portfolio not found: #{portfolio_name}"
        exit 1
      end

      puts "📊 Before Rebalancing:"
      puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
      puts "   Swing Capital: ₹#{portfolio.swing_capital.round(2)}"
      puts "   Long-Term Capital: ₹#{portfolio.long_term_capital.round(2)}"
      puts "   Cash: ₹#{portfolio.available_cash.round(2)}"

      if new_equity
        portfolio.update!(total_equity: new_equity)
        puts "\n💰 Updated equity to: ₹#{new_equity.round(2)}"
      end

      result = PortfolioServices::CapitalBucketer.new(portfolio: portfolio).call

      if result[:success]
        portfolio.reload
        puts "\n📊 After Rebalancing:"
        puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
        puts "   Swing Capital: ₹#{portfolio.swing_capital.round(2)}"
        puts "   Long-Term Capital: ₹#{portfolio.long_term_capital.round(2)}"
        puts "   Cash: ₹#{portfolio.available_cash.round(2)}"

        puts "\n📈 Allocation:"
        puts "   Phase: #{result[:phase]}"
        puts "   Swing: #{result[:allocation][:swing]}%"
        puts "   Long-Term: #{result[:allocation][:long_term]}%"
        puts "   Cash: #{result[:allocation][:cash]}%"

        puts "\n✅ Test completed successfully!"
      else
        puts "❌ Rebalancing failed"
        exit 1
      end
    end
  end
end
