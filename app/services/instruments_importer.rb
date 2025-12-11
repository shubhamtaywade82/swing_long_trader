# app/services/instruments_importer.rb
# frozen_string_literal: true

require 'csv'
require 'open-uri'
require 'yaml'

class InstrumentsImporter
  CSV_URL         = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'
  CACHE_PATH      = Rails.root.join('tmp/dhan_scrip_master.csv')
  CACHE_MAX_AGE   = 24.hours
  VALID_EXCHANGES = %w[NSE BSE].freeze
  BATCH_SIZE      = 1_000
  UNIVERSE_FILE   = Rails.root.join('config/universe/master_universe.yml')

  class << self
    # ------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------
    def import_from_url
      started_at = Time.current
      csv_text   = fetch_csv_with_cache
      summary    = import_from_csv(csv_text)

      finished_at = Time.current
      summary[:started_at]  = started_at
      summary[:finished_at] = finished_at
      summary[:duration]    = finished_at - started_at

      record_success!(summary)
      summary
    end

    # ------------------------------------------------------------
    # Fetch CSV with 24-hour cache
    # ------------------------------------------------------------
    def fetch_csv_with_cache
      if CACHE_PATH.exist? && Time.current - CACHE_PATH.mtime < CACHE_MAX_AGE
        return CACHE_PATH.read
      end

      csv_text = URI.open(CSV_URL, &:read) # rubocop:disable Security/Open

      CACHE_PATH.dirname.mkpath
      File.write(CACHE_PATH, csv_text)

      csv_text
    rescue StandardError => e
      raise e if CACHE_PATH.exist? == false # don't swallow if no fallback

      # Fallback to cached CSV (may be stale)
      CACHE_PATH.read
    end
    private :fetch_csv_with_cache

    def import_from_csv(csv_content)
      instruments_rows = build_batches(csv_content)

      instrument_import = instruments_rows.empty? ? nil : import_instruments!(instruments_rows)

      {
        instrument_rows: instruments_rows.size,
        instrument_upserts: instrument_import&.ids&.size.to_i,
        instrument_total: Instrument.count
      }
    end

    private

    # ------------------------------------------------------------
    # 1. Split CSV rows (swing trading only needs instruments, not derivatives)
    # Optionally filter by universe whitelist if master_universe.yml exists
    # ------------------------------------------------------------
    def build_batches(csv_content)
      instruments = []
      universe_symbols = load_universe_symbols

      CSV.parse(csv_content, headers: true).each do |row|
        next unless VALID_EXCHANGES.include?(row['EXCH_ID'])
        # Skip derivatives (SEGMENT='D') - swing trading uses equity/index instruments only
        next if row['SEGMENT'] == 'D'

        # Filter by universe whitelist if available
        if universe_symbols.present?
          symbol_name = row['SYMBOL_NAME']&.strip&.upcase
          # Remove suffix like -EQ, -BE, etc. for matching
          clean_symbol = symbol_name&.split('-')&.first
          next unless universe_symbols.include?(clean_symbol)
        end

        attrs = build_attrs(row)
        instruments << attrs.slice(*Instrument.column_names.map(&:to_sym))
      end

      instruments
    end

    def load_universe_symbols
      return Set.new unless UNIVERSE_FILE.exist?

      begin
        symbols = YAML.load_file(UNIVERSE_FILE)
        Set.new(symbols.map(&:to_s).map(&:upcase))
      rescue StandardError => e
        Rails.logger.warn("[InstrumentsImporter] Failed to load universe: #{e.message}")
        Set.new
      end
    end
    private :load_universe_symbols

    def build_attrs(row)
      now = Time.zone.now
      {
        security_id: row['SECURITY_ID'],
        exchange: row['EXCH_ID'],
        segment: row['SEGMENT'],
        isin: row['ISIN'],
        instrument_code: row['INSTRUMENT'],
        underlying_security_id: row['UNDERLYING_SECURITY_ID'],
        underlying_symbol: row['UNDERLYING_SYMBOL'],
        symbol_name: row['SYMBOL_NAME'],
        display_name: row['DISPLAY_NAME'],
        instrument_type: row['INSTRUMENT_TYPE'],
        series: row['SERIES'],
        lot_size: row['LOT_SIZE']&.to_i,
        expiry_date: safe_date(row['SM_EXPIRY_DATE']),
        strike_price: row['STRIKE_PRICE']&.to_f,
        option_type: row['OPTION_TYPE'],
        tick_size: row['TICK_SIZE']&.to_f,
        expiry_flag: row['EXPIRY_FLAG'],
        bracket_flag: row['BRACKET_FLAG'],
        cover_flag: row['COVER_FLAG'],
        asm_gsm_flag: row['ASM_GSM_FLAG'],
        asm_gsm_category: row['ASM_GSM_CATEGORY'],
        buy_sell_indicator: row['BUY_SELL_INDICATOR'],
        buy_co_min_margin_per: row['BUY_CO_MIN_MARGIN_PER']&.to_f,
        sell_co_min_margin_per: row['SELL_CO_MIN_MARGIN_PER']&.to_f,
        buy_co_sl_range_max_perc: row['BUY_CO_SL_RANGE_MAX_PERC']&.to_f,
        sell_co_sl_range_max_perc: row['SELL_CO_SL_RANGE_MAX_PERC']&.to_f,
        buy_co_sl_range_min_perc: row['BUY_CO_SL_RANGE_MIN_PERC']&.to_f,
        sell_co_sl_range_min_perc: row['SELL_CO_SL_RANGE_MIN_PERC']&.to_f,
        buy_bo_min_margin_per: row['BUY_BO_MIN_MARGIN_PER']&.to_f,
        sell_bo_min_margin_per: row['SELL_BO_MIN_MARGIN_PER']&.to_f,
        buy_bo_sl_range_max_perc: row['BUY_BO_SL_RANGE_MAX_PERC']&.to_f,
        sell_bo_sl_range_max_perc: row['SELL_BO_SL_RANGE_MAX_PERC']&.to_f,
        buy_bo_sl_range_min_perc: row['BUY_BO_SL_RANGE_MIN_PERC']&.to_f,
        sell_bo_sl_min_range: row['SELL_BO_SL_MIN_RANGE']&.to_f,
        buy_bo_profit_range_max_perc: row['BUY_BO_PROFIT_RANGE_MAX_PERC']&.to_f,
        sell_bo_profit_range_max_perc: row['SELL_BO_PROFIT_RANGE_MAX_PERC']&.to_f,
        buy_bo_profit_range_min_perc: row['BUY_BO_PROFIT_RANGE_MIN_PERC']&.to_f,
        sell_bo_profit_range_min_perc: row['SELL_BO_PROFIT_RANGE_MIN_PERC']&.to_f,
        mtf_leverage: row['MTF_LEVERAGE']&.to_f,
        created_at: now,
        updated_at: now
      }
    end

    # ------------------------------------------------------------
    # 2. Upsert instruments
    # ------------------------------------------------------------
    def import_instruments!(rows)
      Instrument.import(
        rows,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[security_id symbol_name exchange segment],
          columns: %i[
            display_name isin instrument_code instrument_type
            underlying_symbol lot_size tick_size updated_at
          ]
        }
      )
    end

    # ------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------
    def safe_date(str)
      Date.parse(str)
    rescue StandardError
      nil
    end

    def map_segment(char)
      { 'I' => 'index', 'E' => 'equity', 'C' => 'currency',
        'D' => 'derivatives', 'M' => 'commodity' }[char] || char.downcase
    end

    def record_success!(summary)
      Setting.put('instruments.last_imported_at', summary[:finished_at].iso8601)
      Setting.put('instruments.last_import_duration_sec', summary[:duration].to_f.round(2))
      Setting.put('instruments.last_instrument_rows', summary[:instrument_rows])
      Setting.put('instruments.last_instrument_upserts', summary[:instrument_upserts])
      Setting.put('instruments.instrument_total', summary[:instrument_total])
    end
  end
end

