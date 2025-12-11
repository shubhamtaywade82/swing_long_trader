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

ActiveRecord::Schema[8.1].define(version: 2025_12_12_000006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "backtest_positions", force: :cascade do |t|
    t.bigint "backtest_run_id", null: false
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.datetime "entry_date", null: false
    t.decimal "entry_price", precision: 15, scale: 5, null: false
    t.datetime "exit_date"
    t.decimal "exit_price", precision: 15, scale: 5
    t.string "exit_reason"
    t.integer "holding_days"
    t.bigint "instrument_id", null: false
    t.decimal "pnl", precision: 15, scale: 2
    t.decimal "pnl_pct", precision: 10, scale: 4
    t.integer "quantity", null: false
    t.decimal "stop_loss", precision: 15, scale: 5
    t.decimal "take_profit", precision: 15, scale: 5
    t.datetime "updated_at", null: false
    t.index ["backtest_run_id"], name: "index_backtest_positions_on_backtest_run_id"
    t.index ["entry_date", "exit_date"], name: "index_backtest_positions_on_entry_date_and_exit_date"
    t.index ["instrument_id"], name: "index_backtest_positions_on_instrument_id"
  end

  create_table "backtest_runs", force: :cascade do |t|
    t.decimal "annualized_return", precision: 10, scale: 2
    t.text "config"
    t.datetime "created_at", null: false
    t.date "end_date", null: false
    t.decimal "initial_capital", precision: 15, scale: 2, default: "100000.0", null: false
    t.decimal "max_drawdown", precision: 10, scale: 2
    t.text "results"
    t.decimal "risk_per_trade", precision: 5, scale: 2, default: "2.0", null: false
    t.decimal "sharpe_ratio", precision: 10, scale: 4
    t.date "start_date", null: false
    t.string "status", default: "pending"
    t.string "strategy_type", null: false
    t.decimal "total_return", precision: 10, scale: 2
    t.integer "total_trades", default: 0
    t.datetime "updated_at", null: false
    t.decimal "win_rate", precision: 5, scale: 2
    t.index ["start_date", "end_date"], name: "index_backtest_runs_on_start_date_and_end_date"
    t.index ["status"], name: "index_backtest_runs_on_status"
    t.index ["strategy_type"], name: "index_backtest_runs_on_strategy_type"
  end

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
    t.index ["security_id", "exchange", "segment"], name: "index_instruments_unique", unique: true
    t.index ["security_id"], name: "index_instruments_on_security_id"
    t.index ["symbol_name"], name: "index_instruments_on_symbol_name"
    t.index ["underlying_symbol", "expiry_date"], name: "index_instruments_on_underlying_symbol_and_expiry_date", where: "(underlying_symbol IS NOT NULL)"
  end

  create_table "optimization_runs", force: :cascade do |t|
    t.text "all_results"
    t.text "best_metrics"
    t.text "best_parameters"
    t.datetime "created_at", null: false
    t.date "end_date", null: false
    t.text "error_message"
    t.decimal "initial_capital", precision: 15, scale: 2, default: "100000.0", null: false
    t.string "optimization_metric", default: "sharpe_ratio", null: false
    t.text "parameter_ranges"
    t.text "sensitivity_analysis"
    t.date "start_date", null: false
    t.string "status", default: "pending"
    t.string "strategy_type", null: false
    t.integer "total_combinations_tested", default: 0
    t.datetime "updated_at", null: false
    t.boolean "use_walk_forward", default: true
    t.index ["created_at"], name: "index_optimization_runs_on_created_at"
    t.index ["start_date", "end_date"], name: "index_optimization_runs_on_start_date_and_end_date"
    t.index ["status"], name: "index_optimization_runs_on_status"
    t.index ["strategy_type"], name: "index_optimization_runs_on_strategy_type"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "approved_at"
    t.string "approved_by"
    t.decimal "average_price", precision: 15, scale: 2
    t.integer "cancelled_quantity", default: 0
    t.string "client_order_id", null: false
    t.datetime "created_at", null: false
    t.string "dhan_order_id"
    t.text "dhan_response"
    t.decimal "disclosed_quantity", precision: 15, scale: 2, default: "0.0"
    t.boolean "dry_run", default: false
    t.text "error_message"
    t.string "exchange_order_id"
    t.string "exchange_segment", null: false
    t.integer "filled_quantity", default: 0
    t.bigint "instrument_id", null: false
    t.text "metadata"
    t.string "order_type", null: false
    t.integer "pending_quantity", default: 0
    t.decimal "price", precision: 15, scale: 2
    t.string "product_type", null: false
    t.integer "quantity", null: false
    t.datetime "rejected_at"
    t.string "rejected_by"
    t.text "rejection_reason"
    t.boolean "requires_approval", default: false
    t.string "security_id", null: false
    t.string "status", default: "pending"
    t.string "symbol", null: false
    t.string "transaction_type", null: false
    t.decimal "trigger_price", precision: 15, scale: 2
    t.datetime "updated_at", null: false
    t.string "validity", default: "DAY"
    t.index ["client_order_id"], name: "index_orders_on_client_order_id", unique: true
    t.index ["dhan_order_id"], name: "index_orders_on_dhan_order_id"
    t.index ["instrument_id"], name: "index_orders_on_instrument_id"
    t.index ["requires_approval"], name: "index_orders_on_requires_approval"
    t.index ["status", "created_at"], name: "index_orders_on_status_and_created_at"
    t.index ["status"], name: "index_orders_on_status"
  end

  create_table "paper_ledgers", force: :cascade do |t|
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.text "meta"
    t.bigint "paper_portfolio_id", null: false
    t.bigint "paper_position_id"
    t.string "reason", null: false
    t.string "transaction_type", null: false
    t.datetime "updated_at", null: false
    t.index ["paper_portfolio_id", "created_at"], name: "index_paper_ledgers_on_paper_portfolio_id_and_created_at"
    t.index ["paper_portfolio_id"], name: "index_paper_ledgers_on_paper_portfolio_id"
    t.index ["paper_position_id"], name: "index_paper_ledgers_on_paper_position_id"
    t.index ["reason"], name: "index_paper_ledgers_on_reason"
  end

  create_table "paper_portfolios", force: :cascade do |t|
    t.decimal "available_capital", precision: 15, scale: 2, default: "0.0"
    t.decimal "capital", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "max_drawdown", precision: 15, scale: 2, default: "0.0"
    t.text "metadata"
    t.string "name", null: false
    t.decimal "peak_equity", precision: 15, scale: 2, default: "0.0"
    t.decimal "pnl_realized", precision: 15, scale: 2, default: "0.0"
    t.decimal "pnl_unrealized", precision: 15, scale: 2, default: "0.0"
    t.decimal "reserved_capital", precision: 15, scale: 2, default: "0.0"
    t.decimal "total_equity", precision: 15, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_paper_portfolios_on_name", unique: true
  end

  create_table "paper_positions", force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.decimal "current_price", precision: 15, scale: 2, null: false
    t.string "direction", null: false
    t.decimal "entry_price", precision: 15, scale: 2, null: false
    t.decimal "exit_price", precision: 15, scale: 2
    t.string "exit_reason"
    t.integer "holding_days", default: 0
    t.bigint "instrument_id", null: false
    t.text "metadata"
    t.datetime "opened_at", null: false
    t.bigint "paper_portfolio_id", null: false
    t.decimal "pnl", precision: 15, scale: 2, default: "0.0"
    t.decimal "pnl_pct", precision: 8, scale: 2, default: "0.0"
    t.integer "quantity", null: false
    t.decimal "sl", precision: 15, scale: 2
    t.string "status", default: "open"
    t.decimal "tp", precision: 15, scale: 2
    t.datetime "updated_at", null: false
    t.index ["instrument_id"], name: "index_paper_positions_on_instrument_id"
    t.index ["paper_portfolio_id", "opened_at"], name: "index_paper_positions_on_paper_portfolio_id_and_opened_at"
    t.index ["paper_portfolio_id"], name: "index_paper_positions_on_paper_portfolio_id"
    t.index ["status", "paper_portfolio_id"], name: "index_paper_positions_on_status_and_paper_portfolio_id"
    t.index ["status"], name: "index_paper_positions_on_status"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  add_foreign_key "backtest_positions", "backtest_runs"
  add_foreign_key "backtest_positions", "instruments"
  add_foreign_key "candle_series", "instruments"
  add_foreign_key "orders", "instruments"
  add_foreign_key "paper_ledgers", "paper_portfolios"
  add_foreign_key "paper_ledgers", "paper_positions"
  add_foreign_key "paper_positions", "instruments"
  add_foreign_key "paper_positions", "paper_portfolios"
end
