# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_12_11_000330) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "candle_series", force: :cascade do |t|
    t.decimal "close", precision: 15, scale: 5, null: false
    t.datetime "created_at", null: false
    t.decimal "high", precision: 15, scale: 5, null: false
    t.bigint "instrument_id", null: false
    t.decimal "low", precision: 15, scale: 5, null: false
    t.decimal "open", precision: 15, scale: 5, null: false
    t.string "timeframe", null: false
    t.datetime "timestamp", null: false
    t.datetime "updated_at", null: false
    t.bigint "volume", default: 0
    t.index ["instrument_id", "timeframe", "timestamp"], name: "index_candle_series_on_instrument_timeframe_timestamp", unique: true
    t.index ["instrument_id", "timeframe"], name: "index_candle_series_on_instrument_id_and_timeframe"
    t.index ["instrument_id"], name: "index_candle_series_on_instrument_id"
    t.index ["timestamp"], name: "index_candle_series_on_timestamp"
  end

  create_table "instruments", force: :cascade do |t|
    t.string "asm_gsm_category"
    t.string "asm_gsm_flag"
    t.string "bracket_flag"
    t.decimal "buy_bo_min_margin_per", precision: 8, scale: 2
    t.decimal "buy_bo_profit_range_max_perc", precision: 8, scale: 2
    t.decimal "buy_bo_profit_range_min_perc", precision: 8, scale: 2
    t.decimal "buy_bo_sl_range_max_perc", precision: 8, scale: 2
    t.decimal "buy_bo_sl_range_min_perc", precision: 8, scale: 2
    t.decimal "buy_co_min_margin_per", precision: 8, scale: 2
    t.decimal "buy_co_sl_range_max_perc", precision: 8, scale: 2
    t.decimal "buy_co_sl_range_min_perc", precision: 8, scale: 2
    t.string "buy_sell_indicator"
    t.string "cover_flag"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "exchange", null: false
    t.date "expiry_date"
    t.string "expiry_flag"
    t.string "instrument_code"
    t.string "instrument_type"
    t.string "isin"
    t.integer "lot_size"
    t.decimal "mtf_leverage", precision: 8, scale: 2
    t.string "option_type"
    t.string "security_id", null: false
    t.string "segment", null: false
    t.decimal "sell_bo_min_margin_per", precision: 8, scale: 2
    t.decimal "sell_bo_profit_range_max_perc", precision: 8, scale: 2
    t.decimal "sell_bo_profit_range_min_perc", precision: 8, scale: 2
    t.decimal "sell_bo_sl_min_range", precision: 8, scale: 2
    t.decimal "sell_bo_sl_range_max_perc", precision: 8, scale: 2
    t.decimal "sell_co_min_margin_per", precision: 8, scale: 2
    t.decimal "sell_co_sl_range_max_perc", precision: 8, scale: 2
    t.decimal "sell_co_sl_range_min_perc", precision: 8, scale: 2
    t.string "series"
    t.decimal "strike_price", precision: 15, scale: 5
    t.string "symbol_name"
    t.decimal "tick_size"
    t.string "underlying_security_id"
    t.string "underlying_symbol"
    t.datetime "updated_at", null: false
    t.index ["instrument_code"], name: "index_instruments_on_instrument_code"
    t.index ["security_id", "symbol_name", "exchange", "segment"], name: "index_instruments_unique", unique: true
    t.index ["security_id"], name: "index_instruments_on_security_id", unique: true
    t.index ["symbol_name"], name: "index_instruments_on_symbol_name"
    t.index ["underlying_symbol", "expiry_date"], name: "index_instruments_on_underlying_symbol_and_expiry_date", where: "(underlying_symbol IS NOT NULL)"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  add_foreign_key "candle_series", "instruments"
end
