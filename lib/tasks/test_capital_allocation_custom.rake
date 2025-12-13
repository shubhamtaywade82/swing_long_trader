# frozen_string_literal: true

namespace :test do
  namespace :capital do
    desc "Test Capital Allocation with Custom Balances [swing_balance] [long_term_balance] [total_equity]"
    task :custom_allocation, %i[swing_balance long_term_balance total_equity] => :environment do |_t, args|
      swing_balance = args[:swing_balance]&.to_f
      long_term_balance = args[:long_term_balance]&.to_f
      total_equity = args[:total_equity]&.to_f

      puts "\n💰 Testing Capital Allocation with Custom Balances\n"
      puts "=" * 80

      # If total_equity is provided, use it; otherwise calculate from swing + long_term
      if total_equity
        calculated_cash = total_equity - (swing_balance || 0) - (long_term_balance || 0)
      elsif swing_balance && long_term_balance
        total_equity = swing_balance + long_term_balance + 50_000 # Add 50k cash buffer
        calculated_cash = 50_000
      else
        puts "❌ Please provide either total_equity or both swing_balance and long_term_balance"
        puts "Usage: rails test:capital:custom_allocation[swing_balance,long_term_balance,total_equity]"
        exit 1
      end

      portfolio_name = "Custom Test Portfolio"
      portfolio = CapitalAllocationPortfolio.find_or_initialize_by(name: portfolio_name)
      portfolio.assign_attributes(
        mode: "paper",
        total_equity: total_equity,
        swing_capital: swing_balance || 0,
        long_term_capital: long_term_balance || 0,
        available_cash: calculated_cash,
        peak_equity: total_equity,
      )
      portfolio.save!

      puts "📊 Initial Setup:"
      puts "   Total Equity: ₹#{total_equity.round(2)}"
      puts "   Swing Capital: ₹#{(swing_balance || 0).round(2)}"
      puts "   Long-Term Capital: ₹#{(long_term_balance || 0).round(2)}"
      puts "   Available Cash: ₹#{calculated_cash.round(2)}"

      # Test automatic rebalancing
      puts "\n🔄 Running Automatic Rebalancing..."
      result = Portfolio::CapitalBucketer.new(portfolio: portfolio).call

      portfolio.reload
      puts "\n📊 After Rebalancing:"
      puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
      puts "   Swing Capital: ₹#{portfolio.swing_capital.round(2)}"
      puts "   Long-Term Capital: ₹#{portfolio.long_term_capital.round(2)}"
      puts "   Available Cash: ₹#{portfolio.available_cash.round(2)}"

      bucket = portfolio.capital_bucket
      if bucket
        puts "\n📈 Capital Allocation (Phase: #{result[:phase]}):"
        puts "   Swing: #{bucket.swing_pct}% (₹#{portfolio.swing_capital.round(2)})"
        puts "   Long-Term: #{bucket.long_term_pct}% (₹#{portfolio.long_term_capital.round(2)})"
        puts "   Cash: #{bucket.cash_pct}% (₹#{portfolio.available_cash.round(2)})"
        puts "   Threshold 3L: ₹#{bucket.threshold_3l.round(2)}"
        puts "   Threshold 5L: ₹#{bucket.threshold_5l.round(2)}"
      end

      puts "\n✅ Test completed successfully!"
    end

    desc "Test Swing Trading Capital Allocation with Custom Balance [balance]"
    task :swing_allocation, [:balance] => :environment do |_t, args|
      balance = (args[:balance] || 200_000).to_f

      puts "\n📈 Testing Swing Trading Capital Allocation\n"
      puts "=" * 80

      portfolio_name = "Swing Test Portfolio"
      portfolio = CapitalAllocationPortfolio.find_or_initialize_by(name: portfolio_name)
      portfolio.assign_attributes(
        mode: "paper",
        total_equity: balance,
        available_cash: balance,
        swing_capital: 0,
        long_term_capital: 0,
        peak_equity: balance,
      )
      portfolio.save!

      puts "📊 Initial Setup:"
      puts "   Total Equity: ₹#{balance.round(2)}"

      # Rebalance
      result = ::Portfolio::CapitalBucketer.new(portfolio: portfolio).call
      portfolio.reload

      puts "\n📊 After Allocation:"
      puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
      puts "   Swing Capital: ₹#{portfolio.swing_capital.round(2)} (#{(portfolio.swing_capital / portfolio.total_equity * 100).round(2)}%)"
      puts "   Long-Term Capital: ₹#{portfolio.long_term_capital.round(2)} (#{(portfolio.long_term_capital / portfolio.total_equity * 100).round(2)}%)"
      puts "   Available Cash: ₹#{portfolio.available_cash.round(2)} (#{(portfolio.available_cash / portfolio.total_equity * 100).round(2)}%)"
      puts "   Available Swing Capital: ₹#{portfolio.available_swing_capital.round(2)}"

      bucket = portfolio.capital_bucket
      puts "\n📈 Allocation Phase: #{result[:phase]}"
      puts "   Swing: #{bucket.swing_pct}%"
      puts "   Long-Term: #{bucket.long_term_pct}%"
      puts "   Cash: #{bucket.cash_pct}%"

      # Test position sizing
      puts "\n📏 Testing Position Sizing with Swing Capital..."
      instrument = Instrument.first
      if instrument
        entry_price = 100.0
        stop_loss = 95.0

        position_result = Swing::PositionSizer.call(
          portfolio: portfolio,
          entry_price: entry_price,
          stop_loss: stop_loss,
          instrument: instrument,
        )

        if position_result[:success]
          puts "   ✅ Position sizing successful!"
          puts "   Quantity: #{position_result[:quantity]} shares"
          puts "   Capital Required: ₹#{position_result[:capital_required].round(2)}"
          puts "   Risk Amount: ₹#{position_result[:risk_amount].round(2)}"
          puts "   Risk Percentage: #{position_result[:risk_percentage]}%"
        else
          puts "   ⚠️  Position sizing: #{position_result[:error]}"
        end
      end

      puts "\n✅ Test completed successfully!"
    end

    desc "Test Long-Term Trading Capital Allocation with Custom Balance [balance]"
    task :long_term_allocation, [:balance] => :environment do |_t, args|
      balance = (args[:balance] || 500_000).to_f

      puts "\n📊 Testing Long-Term Trading Capital Allocation\n"
      puts "=" * 80

      portfolio_name = "Long-Term Test Portfolio"
      portfolio = CapitalAllocationPortfolio.find_or_initialize_by(name: portfolio_name)
      portfolio.assign_attributes(
        mode: "paper",
        total_equity: balance,
        available_cash: balance,
        swing_capital: 0,
        long_term_capital: 0,
        peak_equity: balance,
      )
      portfolio.save!

      puts "📊 Initial Setup:"
      puts "   Total Equity: ₹#{balance.round(2)}"

      # Rebalance
      result = ::Portfolio::CapitalBucketer.new(portfolio: portfolio).call
      portfolio.reload

      puts "\n📊 After Allocation:"
      puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
      puts "   Swing Capital: ₹#{portfolio.swing_capital.round(2)} (#{(portfolio.swing_capital / portfolio.total_equity * 100).round(2)}%)"
      puts "   Long-Term Capital: ₹#{portfolio.long_term_capital.round(2)} (#{(portfolio.long_term_capital / portfolio.total_equity * 100).round(2)}%)"
      puts "   Available Cash: ₹#{portfolio.available_cash.round(2)} (#{(portfolio.available_cash / portfolio.total_equity * 100).round(2)}%)"
      puts "   Available Long-Term Capital: ₹#{portfolio.available_long_term_capital.round(2)}"

      bucket = portfolio.capital_bucket
      puts "\n📈 Allocation Phase: #{result[:phase]}"
      puts "   Swing: #{bucket.swing_pct}%"
      puts "   Long-Term: #{bucket.long_term_pct}%"
      puts "   Cash: #{bucket.cash_pct}%"

      # Test long-term allocation
      puts "\n📏 Testing Long-Term Allocation..."
      instruments = Instrument.limit(5)
      if instruments.any?
        allocator = LongTerm::Allocator.new(portfolio: portfolio, instruments: instruments)
        allocation_result = allocator.call

        if allocation_result[:success]
          puts "   ✅ Long-term allocation successful!"
          allocation_result[:allocations].each_with_index do |alloc, idx|
            puts "   #{idx + 1}. #{alloc[:instrument].symbol_name}:"
            puts "      Allocation: #{alloc[:allocation_pct].round(2)}% (₹#{alloc[:allocation_amount].round(2)})"
          end
        else
          puts "   ⚠️  Long-term allocation: #{allocation_result[:error]}"
        end
      end

      puts "\n✅ Test completed successfully!"
    end

    desc "Test All Capital Allocation Scenarios"
    task all_scenarios: :environment do
      puts "\n💰 Testing All Capital Allocation Scenarios\n"
      puts "=" * 80

      scenarios = [
        { name: "Early Stage (< ₹3L)", balance: 200_000 },
        { name: "Growth Stage (₹3L - ₹5L)", balance: 400_000 },
        { name: "Mature Stage (₹5L+)", balance: 600_000 },
        { name: "Large Portfolio (₹10L+)", balance: 1_000_000 },
      ]

      scenarios.each do |scenario|
        puts "\n" + "-" * 80
        puts "📊 Scenario: #{scenario[:name]}"
        puts "-" * 80

        portfolio_name = "Scenario Test - #{scenario[:name]}"
        portfolio = CapitalAllocationPortfolio.find_or_initialize_by(name: portfolio_name)
        portfolio.assign_attributes(
          mode: "paper",
          total_equity: scenario[:balance],
          available_cash: scenario[:balance],
          swing_capital: 0,
          long_term_capital: 0,
          peak_equity: scenario[:balance],
        )
        portfolio.save!

        result = Portfolio::CapitalBucketer.new(portfolio: portfolio).call
        portfolio.reload
        bucket = portfolio.capital_bucket

        puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
        puts "   Phase: #{result[:phase]}"
        puts "   Swing: #{bucket.swing_pct}% (₹#{portfolio.swing_capital.round(2)})"
        puts "   Long-Term: #{bucket.long_term_pct}% (₹#{portfolio.long_term_capital.round(2)})"
        puts "   Cash: #{bucket.cash_pct}% (₹#{portfolio.available_cash.round(2)})"
        puts "   Available Swing: ₹#{portfolio.available_swing_capital.round(2)}"
        puts "   Available Long-Term: ₹#{portfolio.available_long_term_capital.round(2)}"
      end

      puts "\n" + "=" * 80
      puts "✅ All scenarios tested successfully!"
      puts "=" * 80
    end
  end
end

