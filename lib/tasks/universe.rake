# frozen_string_literal: true

require 'csv'
require 'yaml'

namespace :universe do
  desc 'Build master universe whitelist from CSV files in config/universe/csv/'
  task build: :environment do
    csv_dir = Rails.root.join('config/universe/csv')
    output_file = Rails.root.join('config/universe/master_universe.yml')

    unless csv_dir.exist?
      puts "❌ Universe CSV directory not found: #{csv_dir}"
      puts "   Create the directory and add CSV files with instrument symbols"
      exit 1
    end

    csv_files = Dir[csv_dir.join('*.csv')]
    if csv_files.empty?
      puts "⚠️  No CSV files found in #{csv_dir}"
      puts "   Add CSV files with 'Symbol' column containing instrument symbols"
      puts "   Example: NIFTY, BANKNIFTY, RELIANCE, TCS, etc."
      exit 1
    end

    puts "📊 Building master universe from #{csv_files.size} CSV file(s)..."
    symbols = []

    csv_files.each do |csv_file|
      puts "  Reading: #{File.basename(csv_file)}"
      begin
        CSV.foreach(csv_file, headers: true) do |row|
          # Try common column names for symbols
          symbol = row['Symbol'] || row['SYMBOL'] || row['symbol'] ||
                   row['TradingSymbol'] || row['TRADING_SYMBOL'] ||
                   row['SymbolName'] || row['SYMBOL_NAME']

          if symbol.present?
            # Clean symbol (remove suffixes like -EQ, -BE, etc. if needed)
            clean_symbol = symbol.to_s.strip.upcase.split('-').first
            symbols << clean_symbol if clean_symbol.present?
          end
        end
      rescue StandardError => e
        puts "  ⚠️  Error reading #{File.basename(csv_file)}: #{e.message}"
      end
    end

    symbols = symbols.compact.uniq.sort

    if symbols.empty?
      puts "❌ No symbols found in CSV files"
      puts "   Ensure CSV files have a 'Symbol' column with instrument symbols"
      exit 1
    end

    # Ensure output directory exists
    output_file.dirname.mkpath

    # Write to YAML file
    File.write(output_file, symbols.to_yaml)

    puts "\n✅ Master universe built successfully!"
    puts "   Universe size: #{symbols.size} instruments"
    puts "   Output file: #{output_file}"
    puts "\n📋 Sample symbols (first 10):"
    symbols.first(10).each { |s| puts "   - #{s}" }
    puts "   ..." if symbols.size > 10
  end

  desc 'Show current universe statistics'
  task stats: :environment do
    universe_file = Rails.root.join('config/universe/master_universe.yml')

    unless universe_file.exist?
      puts "❌ Universe file not found: #{universe_file}"
      puts "   Run `rails universe:build` first"
      exit 1
    end

    symbols = YAML.load_file(universe_file)
    puts "📊 Universe Statistics:"
    puts "   Total instruments: #{symbols.size}"
    puts "   First 10: #{symbols.first(10).join(', ')}"
    puts "   Last 10: #{symbols.last(10).join(', ')}"
  end

  desc 'Validate universe against imported instruments'
  task validate: :environment do
    universe_file = Rails.root.join('config/universe/master_universe.yml')

    unless universe_file.exist?
      puts "❌ Universe file not found: #{universe_file}"
      puts "   Run `rails universe:build` first"
      exit 1
    end

    universe_symbols = YAML.load_file(universe_file).to_set
    imported_symbols = Instrument.pluck(:symbol_name).compact.map(&:upcase).to_set

    matched = universe_symbols & imported_symbols
    missing = universe_symbols - imported_symbols
    extra = imported_symbols - universe_symbols

    puts "📊 Universe Validation:"
    puts "   Universe size: #{universe_symbols.size}"
    puts "   Imported instruments: #{imported_symbols.size}"
    puts "   Matched: #{matched.size} (#{(matched.size.to_f / universe_symbols.size * 100).round(1)}%)"
    puts "   Missing from DB: #{missing.size}"
    puts "   Extra in DB (not in universe): #{extra.size}"

    if missing.any?
      puts "\n⚠️  Missing instruments (first 20):"
      missing.first(20).each { |s| puts "   - #{s}" }
      puts "   ..." if missing.size > 20
    end
  end
end

