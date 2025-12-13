# frozen_string_literal: true

class CreateLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :ledger_entries, if_not_exists: true do |t|
      t.references :portfolio, null: false, foreign_key: { to_table: :capital_allocation_portfolios }, index: true
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.string :reason, null: false # deposit | withdrawal | trade_pnl | rebalance | capital_allocation
      t.string :entry_type, null: false # debit | credit
      t.references :swing_position, foreign_key: true, null: true
      t.references :long_term_holding, foreign_key: true, null: true
      t.text :metadata

      t.timestamps
    end

    unless index_exists?(:ledger_entries, [:portfolio_id, :created_at])
      add_index :ledger_entries, [:portfolio_id, :created_at]
    end

    unless index_exists?(:ledger_entries, :reason)
      add_index :ledger_entries, :reason
    end

    unless index_exists?(:ledger_entries, [:portfolio_id, :reason])
      add_index :ledger_entries, [:portfolio_id, :reason]
    end
  end
end
