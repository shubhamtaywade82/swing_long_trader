# frozen_string_literal: true

require "csv"
require "yaml"
require "open-uri"
require "fileutils"

# NSE Index CSV URLs to download
# Curated for Swing + Long-Term Trading
# Focus: Quality stocks with good liquidity, excludes micro caps and penny stocks
NSE_INDEX_URLS = {
  # Core Large Cap Indices (High Liquidity, Stable)
  "nifty50" => "https://www.niftyindices.com/IndexConstituent/ind_nifty50list.csv",
  "nifty_next50" => "https://www.niftyindices.com/IndexConstituent/ind_niftynext50list.csv",
  "nifty100" => "https://www.niftyindices.com/IndexConstituent/ind_nifty100list.csv",
  "nifty200" => "https://www.niftyindices.com/IndexConstituent/ind_nifty200list.csv",
  "nifty500" => "https://www.niftyindices.com/IndexConstituent/ind_nifty500list.csv",
  # Mid Cap Indices (Growth Potential, Good for Swing Trading)
  "nifty_midcap150" => "https://www.niftyindices.com/IndexConstituent/ind_niftymidcap150list.csv",
  "nifty_midcap100" => "https://www.niftyindices.com/IndexConstituent/ind_niftymidcap100list.csv",
  "nifty_midcap50" => "https://www.niftyindices.com/IndexConstituent/ind_niftymidcap50list.csv",
  # Small Cap Indices (Selective - Quality Small Caps Only)
  "nifty_smallcap250" => "https://www.niftyindices.com/IndexConstituent/ind_niftysmallcap250list.csv",
  "nifty_smallcap100" => "https://www.niftyindices.com/IndexConstituent/ind_niftysmallcap100list.csv",
  "nifty_smallcap50" => "https://www.niftyindices.com/IndexConstituent/ind_niftysmallcap50list.csv",
  # Sector Indices (Diversification)
  "nifty_bank" => "https://www.niftyindices.com/IndexConstituent/ind_niftybanklist.csv",
  "nifty_it" => "https://www.niftyindices.com/IndexConstituent/ind_niftyitlist.csv",
  "nifty_fmcg" => "https://www.niftyindices.com/IndexConstituent/ind_niftyfmcglist.csv",
  "nifty_pharma" => "https://www.niftyindices.com/IndexConstituent/ind_niftypharmalist.csv",
  "nifty_auto" => "https://www.niftyindices.com/IndexConstituent/ind_niftyautolist.csv",
  # Excluded: Nifty Microcap 250 (too risky), Nifty Total Market (too broad)
  # Excluded: Nifty500 Multicap/LargeMidSmall (already covered by Nifty 500)
  # Excluded: Nifty MidSmallcap 400 (covered by Midcap 150 + Smallcap 250)
  # Excluded: Nifty LargeMidcap 250 (covered by Nifty 200/500)
}.freeze

namespace :universe do
  desc "Build master universe whitelist from NSE index CSVs (downloads automatically)"
  task build: :environment do
    require "net/http"

    # Helper method to download CSV with retry
    download_csv = lambda do |url, max_retries: 2|
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60
      http.open_timeout = 30

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

      retries = 0
      begin
        response = http.request(request)
        raise "HTTP #{response.code}" unless response.code == "200"

        response.body
      rescue StandardError => e
        retries += 1
        raise e unless retries <= max_retries

        sleep(2 * retries) # Exponential backoff
        retry
      end
    end

    csv_dir = Rails.root.join("tmp/universe/csv")
    csv_max_age = 24.hours # Only download if file is older than 24 hours

    # Ensure CSV directory exists
    csv_dir.mkpath

    puts "📥 Checking NSE index CSVs..."
    downloaded_files = []
    skipped_files = []

    # Helper to validate CSV file
    validate_csv_file = lambda do |file_path|
      return false unless file_path.exist?
      return false if file_path.size.zero? # Empty file

      # Try to parse first few lines to check if it's valid CSV
      begin
        line_count = 0
        CSV.foreach(file_path, headers: true) do |_row|
          line_count += 1
          break if line_count >= 2 # Just check if we can read at least 2 rows (header + 1 data row)
        end
        line_count.positive? # Valid if we can read at least one data row
      rescue StandardError
        false # Invalid CSV
      end
    end

    NSE_INDEX_URLS.each do |name, url|
      csv_file = csv_dir.join("#{name}.csv")

      # Check if file exists, is recent, and is valid
      if csv_file.exist? && (Time.current - csv_file.mtime) < csv_max_age
        if validate_csv_file.call(csv_file)
          puts "  ⏭️  Skipping #{name} (file exists and is recent: #{((Time.current - csv_file.mtime) / 1.hour).round(1)}h old)"
          skipped_files << csv_file
          next
        else
          puts "  ⚠️  Existing file for #{name} is invalid/corrupted, will re-download..."
          # File exists but is invalid, so we'll download a new one
        end
      end

      begin
        puts "  Downloading #{name}#{csv_file.exist? ? " (file is #{((Time.current - csv_file.mtime) / 1.hour).round(1)}h old)" : ' (file not found)'}..."
        csv_content = download_csv.call(url)

        # Validate downloaded content before writing
        raise "Downloaded content is empty or invalid" unless csv_content.present? && csv_content.lines.count >= 2

        # Create backup of existing file before overwriting (if it exists and is valid)
        if csv_file.exist? && validate_csv_file.call(csv_file)
          backup_file = csv_file.dirname.join("#{csv_file.basename}.backup")
          FileUtils.cp(csv_file, backup_file)
          puts "    💾 Backed up existing file to #{backup_file.basename}"
        end

        # Write new file
        File.write(csv_file, csv_content)

        # Validate the written file
        raise "Downloaded file failed validation after writing" unless validate_csv_file.call(csv_file)

        downloaded_files << csv_file
        puts "    ✅ Saved to #{csv_file.basename}"
      rescue StandardError => e
        puts "    ⚠️  Failed to download #{name}: #{e.message}"
        # If download fails but existing file is valid, use existing file
        if csv_file.exist? && validate_csv_file.call(csv_file)
          puts "    ℹ️  Using existing valid file: #{csv_file.basename}"
          skipped_files << csv_file
        elsif csv_file.exist?
          puts "    ❌ Existing file is also invalid, #{name} will be skipped"
        end
        # Continue with other indices even if one fails
      end
    end

    # Collect all CSV files (downloaded + skipped + manually added)
    manual_csv_files = Dir[csv_dir.join("*.csv")] - downloaded_files - skipped_files
    csv_files = downloaded_files + skipped_files + manual_csv_files

    if csv_files.empty?
      puts "❌ No CSV files available"
      puts "   Failed to download NSE index CSVs and no manual CSVs found"
      exit 1
    end

    puts "\n📊 Building master universe from #{csv_files.size} CSV file(s)..."
    puts "  Step 1: Collecting data from all CSV files..."

    # Step 1: Collect all records from all CSV files
    all_records = {}
    csv_files.each do |csv_file|
      index_name = File.basename(csv_file, ".csv").upcase
      puts "  Reading: #{File.basename(csv_file)} (Index: #{index_name})"
      file_records = 0

      begin
        CSV.foreach(csv_file, headers: true) do |row|
          # Extract data from CSV
          company_name = row["Company Name"] || row["company_name"] || row["COMPANY_NAME"]
          industry = row["Industry"] || row["industry"] || row["INDUSTRY"]
          symbol = row["Symbol"] || row["SYMBOL"] || row["symbol"] ||
                   row["TradingSymbol"] || row["TRADING_SYMBOL"] ||
                   row["SymbolName"] || row["SYMBOL_NAME"]
          series = row["Series"] || row["SERIES"] || row["series"]
          isin_code = row["ISIN Code"] || row["ISIN"] || row["isin"] || row["Isin"] ||
                      row["ISIN_CODE"] || row["isin_code"]

          next unless symbol.present? && company_name.present?

          # Clean symbol (remove known suffixes like -EQ, -BE, -BZ, etc.)
          # But preserve hyphens in symbol names like "BAJAJ-AUTO"
          clean_symbol = symbol.to_s.strip.upcase
          known_suffixes = %w[-EQ -BE -BZ -BL -BT -GC -GD -GO -GP -GS -GT -GU -GV -GW -GX -GY -GZ]
          known_suffixes.each do |suffix|
            clean_symbol = clean_symbol.delete_suffix(suffix) if clean_symbol.end_with?(suffix)
          end
          next unless clean_symbol.present?

          # Normalize ISIN
          clean_isin = isin_code&.strip&.upcase
          clean_isin = nil if clean_isin.blank?

          # Use symbol as key for deduplication (case-insensitive)
          # If symbol already exists, prefer record with ISIN code or more complete data
          if all_records.key?(clean_symbol)
            existing = all_records[clean_symbol]
            # Skip if existing record has ISIN and current doesn't
            next if existing[:isin_code].present? && clean_isin.blank?
            # Skip if existing record has complete data and current is incomplete
            next if existing[:company_name].present? && existing[:industry].present? &&
                    (company_name.strip.blank? || industry&.strip.blank?)
          end

          # Store or replace the record for this symbol
          all_records[clean_symbol] = {
            company_name: company_name.strip,
            industry: industry&.strip,
            symbol: clean_symbol,
            series: series&.strip,
            isin_code: clean_isin,
            index_name: index_name, # Keep track of which index it came from (first occurrence)
          }
          file_records += 1
        end
        puts "    ✅ Collected #{file_records} records"
      rescue StandardError => e
        puts "  ⚠️  Error reading #{File.basename(csv_file)}: #{e.message}"
      end
    end

    puts "  Step 2: Deduplicating records..."
    unique_count = all_records.size
    puts "    ✅ Found #{unique_count} unique symbols (deduplicated)"

    puts "  Step 3: Inserting unique records into database..."
    # Clear existing data
    puts "  Clearing existing index constituents..."
    IndexConstituent.delete_all

    total_inserted = 0
    total_skipped = 0

    all_records.each do |symbol, record|
      IndexConstituent.create!(
        company_name: record[:company_name],
        industry: record[:industry],
        symbol: record[:symbol],
        series: record[:series],
        isin_code: record[:isin_code],
        index_name: record[:index_name],
      )
      total_inserted += 1
    rescue StandardError => e
      puts "    ⚠️  Error inserting #{symbol}: #{e.message}"
      total_skipped += 1
    end

    # Get statistics
    total_count = IndexConstituent.count
    unique_symbols = IndexConstituent.distinct.count(:symbol)
    with_isin = IndexConstituent.with_isin.count
    without_isin = total_count - with_isin

    puts "\n✅ Master universe built successfully!"
    puts "   Total records: #{total_count}"
    puts "   Unique symbols: #{unique_symbols}"
    puts "   Records with ISIN: #{with_isin}"
    puts "   Records without ISIN: #{without_isin}"
    puts "   Records inserted: #{total_inserted}"
    puts "   Records skipped (errors): #{total_skipped}"
    puts "\n📋 Sample entries (first 5):"
    IndexConstituent.order(:symbol).limit(5).each do |entry|
      isin_str = entry.isin_code.present? ? " (ISIN: #{entry.isin_code})" : " (no ISIN)"
      puts "   - #{entry.symbol} - #{entry.company_name}#{isin_str}"
    end
    puts "   ..." if total_count > 5
  end

  desc "Show current universe statistics"
  task stats: :environment do
    total_count = IndexConstituent.count
    unique_symbols = IndexConstituent.distinct.count(:symbol)
    with_isin = IndexConstituent.with_isin.count
    without_isin = total_count - with_isin

    puts "📊 Universe Statistics:"
    puts "   Total records: #{total_count}"
    puts "   Unique symbols: #{unique_symbols}"
    puts "   Records with ISIN: #{with_isin}"
    puts "   Records without ISIN: #{without_isin}"

    if unique_symbols > 0
      puts "\n📋 Sample symbols (first 10):"
      IndexConstituent.distinct.order(:symbol).limit(10).pluck(:symbol).each do |symbol|
        puts "   - #{symbol}"
      end
      puts "   ..." if unique_symbols > 10
    end
  end

  desc "Validate universe against imported instruments"
  task validate: :environment do
    universe_symbols = IndexConstituent.universe_symbols
    universe_isins = IndexConstituent.universe_isins

    imported_symbols = Instrument.pluck(:symbol_name).compact.map(&:upcase).to_set
    imported_isins = Instrument.pluck(:isin).compact.map(&:upcase).to_set

    # Match by symbol
    matched_by_symbol = universe_symbols & imported_symbols
    missing_by_symbol = universe_symbols - imported_symbols

    # Match by ISIN (if available)
    matched_by_isin = universe_isins & imported_isins
    missing_by_isin = universe_isins - imported_isins

    # Combined match (either symbol or ISIN match)
    total_matched = (matched_by_symbol.size + matched_by_isin.size)
    total_universe = universe_symbols.size

    puts "📊 Universe Validation:"
    puts "   Universe size: #{total_universe}"
    puts "   Imported instruments: #{imported_symbols.size}"
    puts "   Matched by symbol: #{matched_by_symbol.size}"
    puts "   Matched by ISIN: #{matched_by_isin.size}"
    puts "   Total matched: #{total_matched} (#{(total_matched.to_f / total_universe * 100).round(1)}%)"
    puts "   Missing from DB (by symbol): #{missing_by_symbol.size}"
    puts "   Missing from DB (by ISIN): #{missing_by_isin.size}"

    if missing_by_symbol.any?
      puts "\n⚠️  Missing instruments by symbol (first 20):"
      missing_by_symbol.first(20).each { |s| puts "   - #{s}" }
      puts "   ..." if missing_by_symbol.size > 20
    end
  end
end
