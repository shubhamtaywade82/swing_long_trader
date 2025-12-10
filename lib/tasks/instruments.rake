# frozen_string_literal: true

require 'pp'

namespace :instruments do
  desc 'Import instruments from DhanHQ CSV'
  task import: :environment do
    pp 'Starting instruments import...'
    start_time = Time.current

    begin
      result   = InstrumentsImporter.import_from_url
      duration = result[:duration] || (Time.current - start_time)
      pp "\nImport completed successfully in #{duration.round(2)} seconds!"
      pp "Total Instruments: #{result[:instrument_total]}"

      # Show some stats
      pp "\n--- Stats ---"
      pp "NSE Instruments: #{Instrument.nse.count}"
      pp "BSE Instruments: #{Instrument.bse.count}"
      pp "Index Instruments: #{Instrument.segment_index.count}"
      pp "Equity Instruments: #{Instrument.segment_equity.count}"
      pp "Total: #{Instrument.count}"
    rescue StandardError => e
      pp "Import failed: #{e.message}"
      pp e.backtrace.join("\n")
    end
  end

  desc 'Reimport instruments (upserts - adds new, updates existing)'
  task reimport: :environment do
    pp 'Starting instruments reimport (upsert mode)...'
    pp 'Note: Import uses upsert logic - will add new instruments and update existing ones.'
    pp 'Existing instruments will NOT be deleted.'
    pp ''
    Rake::Task['instruments:import'].invoke
  end

  desc 'Clear all instruments (DANGER: Only use if you need to completely reset the database)'
  desc 'Normal imports use upsert and do not require clearing.'
  task :clear, [:force] => :environment do |_t, _args|
    pp '⚠️  WARNING: This will delete ALL instruments!'
    pp '⚠️  This is usually NOT needed since imports use upsert (add/update only).'
    pp ''

    pp 'Proceeding with deletion of all instruments...'
    Instrument.delete_all
    pp '✅ Cleared successfully!'
  end

  desc 'Check instrument inventory freshness and counts'
  task status: :environment do
    last_import_raw = Setting.fetch('instruments.last_imported_at')

    unless last_import_raw
      pp 'No instrument import recorded yet.'
      exit 1
    end

    imported_at = Time.zone.parse(last_import_raw.to_s)
    age_seconds = Time.current - imported_at
    max_age     = InstrumentsImporter::CACHE_MAX_AGE

    pp "Last import at: #{imported_at}"
    pp "Age (seconds): #{age_seconds.round(2)}"
    pp "Import duration (sec): #{Setting.fetch('instruments.last_import_duration_sec', 'unknown')}"
    pp "Last instrument rows: #{Setting.fetch('instruments.last_instrument_rows', '0')}"
    pp "Upserts (instruments): #{Setting.fetch('instruments.last_instrument_upserts', '0')}"
    pp "Total instruments: #{Setting.fetch('instruments.instrument_total', '0')}"

    if age_seconds > max_age
      pp "Status: STALE (older than #{max_age.inspect})"
      exit 1
    end

    pp 'Status: OK'
  rescue ArgumentError => e
    pp "Failed to parse last import timestamp: #{e.message}"
    exit 1
  end
end

# Provide aliases for legacy singular namespace usage.
namespace :instrument do
  desc 'Alias for instruments:import'
  task import: 'instruments:import'

  desc 'Alias for instruments:clear'
  task clear: 'instruments:clear'

  desc 'Alias for instruments:reimport'
  task reimport: 'instruments:reimport'
end

# Test environment specific tasks
namespace :test do
  namespace :instruments do
    desc 'Import instruments for test environment (uses cached CSV if available)'
    task import: :environment do
      unless Rails.env.test?
        puts 'This task is only for test environment. Use `bin/rails instruments:import` for other environments.'
        exit 1
      end

      puts 'Importing instruments for test environment...'

      # Use filtered CSV if available and FILTERED_CSV=true, otherwise use full CSV
      csv_path = if ENV['FILTERED_CSV'] == 'true'
                   filtered_path = Rails.root.join('tmp/dhan_scrip_master_filtered.csv')
                   if filtered_path.exist?
                     puts "Using filtered CSV: #{filtered_path}"
                     filtered_path
                   else
                     puts '⚠️  Filtered CSV not found. Run `RAILS_ENV=test bin/rails test:instruments:filter_csv` first.'
                     puts 'Falling back to full CSV...'
                     Rails.root.join('tmp/dhan_scrip_master.csv')
                   end
                 else
                   Rails.root.join('tmp/dhan_scrip_master.csv')
                 end

      if csv_path.exist?
        csv_type = csv_path.basename.to_s.include?('filtered') ? 'filtered' : 'full'
        puts "Using #{csv_type} CSV: #{csv_path}"
        csv_content = csv_path.read
      else
        puts "CSV cache not found at #{csv_path}"
        puts 'Downloading from DhanHQ...'
        csv_content = InstrumentsImporter.fetch_csv_with_cache
      end

      result = InstrumentsImporter.import_from_csv(csv_content)
      puts "\n✅ Import completed!"
      puts "Instruments: #{result[:instrument_upserts]} upserted, #{result[:instrument_total]} total"
    end

    desc 'Check if instruments are imported in test environment'
    task status: :environment do
      unless Rails.env.test?
        puts 'This task is only for test environment.'
        exit 1
      end

      instrument_count = Instrument.count
      nifty = Instrument.segment_index.find_by(symbol_name: 'NIFTY')
      banknifty = Instrument.segment_index.find_by(symbol_name: 'BANKNIFTY')

      puts 'Test Environment Instrument Status:'
      puts "  Instruments: #{instrument_count}"
      puts "  NIFTY index: #{nifty ? "✅ (security_id: #{nifty.security_id})" : '❌ Not found'}"
      puts "  BANKNIFTY index: #{banknifty ? "✅ (security_id: #{banknifty.security_id})" : '❌ Not found'}"

      puts "\n⚠️  No instruments found. Run: RAILS_ENV=test bin/rails test:instruments:import" if instrument_count.zero?
    end
  end
end

# Filter CSV for test environment (index instruments only)
namespace :test do
  namespace :instruments do
    desc 'Create filtered CSV with only NIFTY, BANKNIFTY, SENSEX indexes'
    task filter_csv: :environment do
      require 'csv'

      unless Rails.env.test?
        puts 'This task is only for test environment.'
        exit 1
      end

      source_csv = Rails.root.join('tmp/dhan_scrip_master.csv')
      filtered_csv = Rails.root.join('tmp/dhan_scrip_master_filtered.csv')

      unless source_csv.exist?
        puts "❌ Source CSV not found: #{source_csv}"
        puts 'Run `bin/rails instruments:import` first to download the CSV.'
        exit 1
      end

      puts "Reading source CSV: #{source_csv}"
      puts "Writing filtered CSV: #{filtered_csv}"

      target_symbols = %w[NIFTY BANKNIFTY SENSEX]
      index_count = 0
      total_rows = 0

      CSV.open(filtered_csv, 'w') do |out_csv|
        CSV.foreach(source_csv, headers: true) do |row|
          total_rows += 1

          # Include row if:
          # 1. Index instrument (SEGMENT='I') with SYMBOL_NAME in target symbols
          # Skip derivatives (SEGMENT='D') - swing trading doesn't need them
          segment = row['SEGMENT']
          symbol_name = row['SYMBOL_NAME']

          is_index = segment == 'I' && target_symbols.include?(symbol_name)

          if is_index
            # Write header on first match
            out_csv << row.headers if index_count.zero?

            out_csv << row.fields
            index_count += 1
          end

          # Progress indicator every 50k rows
          if total_rows % 50_000 == 0
            print '.'
            $stdout.flush
          end
        end
      end

      puts "\n✅ Filtered CSV created successfully!"
      puts "  Total rows processed: #{total_rows}"
      puts "  Index instruments: #{index_count}"
      puts "  Total rows in filtered CSV: #{index_count}"
      puts "\n📁 Filtered CSV saved to: #{filtered_csv}"
      puts "\n💡 Use this filtered CSV for faster test imports:"
      puts '   Set FILTERED_CSV=true when importing in test environment'
    end
  end
end

