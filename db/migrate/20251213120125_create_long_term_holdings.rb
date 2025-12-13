# frozen_string_literal: true

class CreateLongTermHoldings < ActiveRecord::Migration[8.1]
  def change
    create_table :long_term_holdings, if_not_exists: true do |t|
      t.references :portfolio, null: false, foreign_key: { to_table: :capital_allocation_portfolios }, index: true
      t.references :instrument, null: false, foreign_key: { to_table: :instruments }, index: true
      t.decimal :avg_price, precision: 15, scale: 5, null: false
      t.integer :quantity, null: false
      t.decimal :allocation_pct, precision: 5, scale: 2, null: false # Percentage of long_term_capital
      t.decimal :current_value, precision: 15, scale: 2, default: 0.0
      t.decimal :unrealized_pnl, precision: 15, scale: 2, default: 0.0
      t.date :purchased_at, null: false
      t.date :last_rebalanced_at
      t.text :metadata

      t.timestamps
    end

    unless index_exists?(:long_term_holdings, [:portfolio_id, :instrument_id])
      add_index :long_term_holdings, [:portfolio_id, :instrument_id], unique: true
    end

    unless index_exists?(:long_term_holdings, :portfolio_id)
      add_index :long_term_holdings, :portfolio_id
    end
  end
end
