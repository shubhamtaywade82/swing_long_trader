# frozen_string_literal: true

namespace :metrics do
  desc 'Show daily metrics'
  task daily: :environment do
    date = ENV['DATE'] ? Date.parse(ENV['DATE']) : Date.today
    stats = Metrics::Tracker.get_daily_stats(date)

    openai_cost = Metrics::Tracker.get_openai_daily_cost(date)

    puts "📊 Daily Metrics for #{date}"
    puts "=" * 60
    puts "DhanHQ API Calls: #{stats[:dhan_api_calls]}"
    puts "OpenAI API Calls: #{stats[:openai_api_calls]}"
    puts "OpenAI Cost: $#{openai_cost.round(4)}"
    puts "Candidates Found: #{stats[:candidate_count]}"
    puts "Signals Generated: #{stats[:signal_count]}"
    puts "Failed Jobs: #{stats[:failed_jobs]}"

    # Order metrics
    orders_placed = Metrics::Tracker.get_orders_placed(date)
    orders_failed = Metrics::Tracker.get_orders_failed(date)
    puts "\nOrders:"
    puts "  Placed: #{orders_placed}"
    puts "  Failed: #{orders_failed}"

    # P&L metrics
    daily_pnl = Metrics::PnlTracker.get_daily_pnl(date)
    puts "\nP&L:"
    puts "  Daily: ₹#{daily_pnl.round(2)}"
    puts "=" * 60
  end

  desc 'Show weekly metrics summary'
  task weekly: :environment do
    end_date = Date.today
    start_date = end_date - 7.days

    puts "📊 Weekly Metrics (#{start_date} to #{end_date})"
    puts "=" * 60

    total_dhan = 0
    total_openai = 0
    total_openai_cost = 0.0
    total_candidates = 0
    total_signals = 0
    total_failed = 0

    (start_date..end_date).each do |date|
      stats = Metrics::Tracker.get_daily_stats(date)
      total_dhan += stats[:dhan_api_calls]
      total_openai += stats[:openai_api_calls]
      total_openai_cost += Metrics::Tracker.get_openai_daily_cost(date)
      total_candidates += stats[:candidate_count]
      total_signals += stats[:signal_count]
      total_failed += stats[:failed_jobs]
    end

    puts "Total DhanHQ API Calls: #{total_dhan}"
    puts "Total OpenAI API Calls: #{total_openai}"
    puts "Total OpenAI Cost: $#{total_openai_cost.round(4)}"
    puts "Total Candidates: #{total_candidates}"
    puts "Total Signals: #{total_signals}"
    puts "Total Failed Jobs: #{total_failed}"

    # Order metrics
    week_orders_placed = (start_date..end_date).sum { |d| Metrics::Tracker.get_orders_placed(d) }
    week_orders_failed = (start_date..end_date).sum { |d| Metrics::Tracker.get_orders_failed(d) }
    puts "\nOrders (Week):"
    puts "  Placed: #{week_orders_placed}"
    puts "  Failed: #{week_orders_failed}"

    # P&L metrics
    weekly_pnl = Metrics::PnlTracker.get_weekly_pnl(start_date)
    puts "\nP&L:"
    puts "  Weekly: ₹#{weekly_pnl.round(2)}"
    puts "=" * 60
  end
end


