# frozen_string_literal: true

class CreatePaperPositions < ActiveRecord::Migration[8.0]
  def change
    create_table :paper_positions, if_not_exists: true do |t|
      t.references :paper_portfolio, null: false, foreign_key: true
      t.references :instrument, null: false, foreign_key: true
      t.string :direction, null: false # long, short
      t.decimal :entry_price, precision: 15, scale: 2, null: false
      t.decimal :current_price, precision: 15, scale: 2, null: false
      t.integer :quantity, null: false
      t.decimal :sl, precision: 15, scale: 2 # stop loss
      t.decimal :tp, precision: 15, scale: 2 # take profit
      t.string :status, default: 'open' # open, closed
      t.datetime :opened_at, null: false
      t.datetime :closed_at
      t.decimal :exit_price, precision: 15, scale: 2
      t.string :exit_reason # sl_hit, tp_hit, manual, time_based, signal_exit
      t.decimal :pnl, precision: 15, scale: 2, default: 0
      t.decimal :pnl_pct, precision: 8, scale: 2, default: 0
      t.integer :holding_days, default: 0
      t.text :metadata # JSON metadata (signal info, risk checks, etc.)

      t.timestamps
    end

    unless index_exists?(:paper_positions, :paper_portfolio_id)
      add_index :paper_positions, :paper_portfolio_id
    end

    unless index_exists?(:paper_positions, :instrument_id)
      add_index :paper_positions, :instrument_id
    end

    unless index_exists?(:paper_positions, :status)
      add_index :paper_positions, :status
    end

    unless index_exists?(:paper_positions, [:status, :paper_portfolio_id])
      add_index :paper_positions, [:status, :paper_portfolio_id]
    end

    unless index_exists?(:paper_positions, [:paper_portfolio_id, :opened_at])
      add_index :paper_positions, [:paper_portfolio_id, :opened_at]
    end
  end
end
