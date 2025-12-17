# frozen_string_literal: true

namespace :market_holidays do
  desc "Fetch and store NSE market holidays for a given year (default: current year)"
  task :fetch, [:year] => :environment do |_t, args|
    year = args[:year]&.to_i || Date.current.year
    puts "\n📅 Fetching NSE market holidays for #{year}..."
    puts "=" * 60

    result = MarketHolidays::Fetcher.fetch_and_store(year: year)

    if result[:success]
      puts "✅ Successfully fetched and stored #{result[:stored]} holidays"
      puts "   Year: #{result[:year]}"
      puts "   Fetched: #{result[:fetched]}"
      puts "   Stored: #{result[:stored]}"
      puts "\n📋 Holidays:"
      result[:holidays]&.each do |holiday|
        puts "   - #{holiday[:date]}: #{holiday[:description]}"
      end
    else
      puts "❌ Failed to fetch holidays: #{result[:error]}"
      puts "   Using manual fallback holidays"
    end

    puts "\n" + "=" * 60
  end

  desc "Fetch holidays for multiple years"
  task :fetch_multiple, [:start_year, :end_year] => :environment do |_t, args|
    start_year = args[:start_year]&.to_i || Date.current.year
    end_year = args[:end_year]&.to_i || Date.current.year

    puts "\n📅 Fetching NSE market holidays for #{start_year}-#{end_year}..."
    puts "=" * 60

    (start_year..end_year).each do |year|
      puts "\n📅 Year #{year}:"
      result = MarketHolidays::Fetcher.fetch_and_store(year: year)
      if result[:success]
        puts "   ✅ Stored #{result[:stored]} holidays"
      else
        puts "   ⚠️  #{result[:error]}"
      end
    end

    puts "\n" + "=" * 60
    puts "✅ Complete!"
  end

  desc "List stored market holidays"
  task list: :environment do
    year = ENV["YEAR"]&.to_i || Date.current.year
    holidays = MarketHoliday.for_year(year).order(:date)

    puts "\n📅 Market Holidays for #{year}"
    puts "=" * 60

    if holidays.any?
      holidays.each do |holiday|
        status = holiday.date < Date.current ? "Past" : holiday.date == Date.current ? "Today" : "Upcoming"
        puts "#{holiday.date.strftime('%Y-%m-%d (%A)')}: #{holiday.description} [#{status}]"
      end
      puts "\nTotal: #{holidays.count} holidays"
    else
      puts "No holidays found for #{year}"
      puts "Run: rails market_holidays:fetch[#{year}]"
    end

    puts "=" * 60
  end

  desc "Check if today is a market holiday"
  task check_today: :environment do
    if MarketHoliday.today_holiday?
      holiday = MarketHoliday.find_by(date: Date.current)
      puts "❌ Today (#{Date.current}) is a market holiday: #{holiday.description}"
    else
      is_weekday = (1..5).include?(Date.current.wday)
      if is_weekday
        puts "✅ Today (#{Date.current}) is a trading day"
      else
        puts "❌ Today (#{Date.current}) is a weekend (not a trading day)"
      end
    end
  end
end
