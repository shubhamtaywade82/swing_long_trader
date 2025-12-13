# frozen_string_literal: true

namespace :test do
  desc "Run all tests (MTF + Capital Allocation)"
  task :all, [:symbol] => :environment do |_t, args|
    symbol = args[:symbol] || "RELIANCE"

    puts "\n" + "=" * 80
    puts "🧪 RUNNING ALL TESTS"
    puts "=" * 80

    # Test Multi-Timeframe
    puts "\n" + "-" * 80
    puts "1️⃣ MULTI-TIMEFRAME TESTS"
    puts "-" * 80

    Rake::Task["test:mtf:analyzer"].invoke(symbol)
    puts "\n"
    Rake::Task["test:mtf:signal"].invoke(symbol)
    puts "\n"
    Rake::Task["test:mtf:ai_eval"].invoke(symbol)

    # Test Capital Allocation
    puts "\n" + "-" * 80
    puts "2️⃣ CAPITAL ALLOCATION TESTS"
    puts "-" * 80

    Rake::Task["test:capital:portfolio"].invoke("Test Portfolio", "paper", "500000")
    puts "\n"
    Rake::Task["test:capital:position_size"].invoke(symbol, "2500", "2400")
    puts "\n"
    Rake::Task["test:capital:risk_manager"].invoke("Test Portfolio")

    puts "\n" + "=" * 80
    puts "✅ ALL TESTS COMPLETED"
    puts "=" * 80
  end

  desc "Quick test (MTF analyzer only)"
  task :quick, [:symbol] => :environment do |_t, args|
    symbol = args[:symbol] || "RELIANCE"
    Rake::Task["test:mtf:analyzer"].invoke(symbol)
  end
end
