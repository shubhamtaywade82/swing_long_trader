# frozen_string_literal: true

namespace :test do
  namespace :capital do
    desc "Test Swing Capital Allocation with Custom Balance [balance]"
    task :swing, [:balance] => :environment do |_t, args|
      balance = (args[:balance] || 200_000).to_f

      puts "\n📈 Testing Swing Trading Capital Allocation\n"
      puts "=" * 80

      portfolio_name = "Swing Test - ₹#{balance.round(0)}"
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

      # Rebalance using the model method
      portfolio.rebalance_capital!
      portfolio.reload

      puts "\n📊 After Allocation:"
      puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
      puts "   Swing Capital: ₹#{portfolio.swing_capital.round(2)} (#{(portfolio.swing_capital / portfolio.total_equity * 100).round(2)}%)"
      puts "   Long-Term Capital: ₹#{portfolio.long_term_capital.round(2)} (#{(portfolio.long_term_capital / portfolio.total_equity * 100).round(2)}%)"
      puts "   Available Cash: ₹#{portfolio.available_cash.round(2)} (#{(portfolio.available_cash / portfolio.total_equity * 100).round(2)}%)"
      puts "   Available Swing Capital: ₹#{portfolio.available_swing_capital.round(2)}"

      bucket = portfolio.capital_bucket
      if bucket
        puts "\n📈 Allocation Phase: #{bucket.phase}"
        puts "   Swing: #{bucket.swing_pct}%"
        puts "   Long-Term: #{bucket.long_term_pct}%"
        puts "   Cash: #{bucket.cash_pct}%"
      end

      puts "\n✅ Test completed successfully!"
    end

    desc "Test Long-Term Capital Allocation with Custom Balance [balance]"
    task :long_term, [:balance] => :environment do |_t, args|
      balance = (args[:balance] || 500_000).to_f

      puts "\n📊 Testing Long-Term Trading Capital Allocation\n"
      puts "=" * 80

      portfolio_name = "Long-Term Test - ₹#{balance.round(0)}"
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
      portfolio.rebalance_capital!
      portfolio.reload

      puts "\n📊 After Allocation:"
      puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
      puts "   Swing Capital: ₹#{portfolio.swing_capital.round(2)} (#{(portfolio.swing_capital / portfolio.total_equity * 100).round(2)}%)"
      puts "   Long-Term Capital: ₹#{portfolio.long_term_capital.round(2)} (#{(portfolio.long_term_capital / portfolio.total_equity * 100).round(2)}%)"
      puts "   Available Cash: ₹#{portfolio.available_cash.round(2)} (#{(portfolio.available_cash / portfolio.total_equity * 100).round(2)}%)"
      puts "   Available Long-Term Capital: ₹#{portfolio.available_long_term_capital.round(2)}"

      bucket = portfolio.capital_bucket
      if bucket
        puts "\n📈 Allocation Phase: #{bucket.phase}"
        puts "   Swing: #{bucket.swing_pct}%"
        puts "   Long-Term: #{bucket.long_term_pct}%"
        puts "   Cash: #{bucket.cash_pct}%"
      end

      puts "\n✅ Test completed successfully!"
    end

    desc "Test All Capital Allocation Scenarios"
    task all: :environment do
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

        portfolio_name = "Scenario - #{scenario[:name]}"
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

        portfolio.rebalance_capital!
        portfolio.reload
        bucket = portfolio.capital_bucket

        puts "   Total Equity: ₹#{portfolio.total_equity.round(2)}"
        puts "   Phase: #{bucket.phase}"
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

