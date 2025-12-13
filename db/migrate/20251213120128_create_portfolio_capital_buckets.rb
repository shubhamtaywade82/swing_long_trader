# frozen_string_literal: true

class CreatePortfolioCapitalBuckets < ActiveRecord::Migration[8.1]
  def change
    create_table :portfolio_capital_buckets, if_not_exists: true do |t|
      t.references :portfolio, null: false, foreign_key: { to_table: :capital_allocation_portfolios }, index: true, unique: true
      t.decimal :swing_pct, precision: 5, scale: 2, default: 80.0, null: false # Percentage
      t.decimal :long_term_pct, precision: 5, scale: 2, default: 0.0, null: false # Percentage
      t.decimal :cash_pct, precision: 5, scale: 2, default: 20.0, null: false # Percentage
      t.decimal :threshold_3l, precision: 15, scale: 2, default: 300_000.0 # ₹3L threshold
      t.decimal :threshold_5l, precision: 15, scale: 2, default: 500_000.0 # ₹5L threshold
      t.boolean :auto_rebalance, default: true, null: false

      t.timestamps
    end

    unless index_exists?(:portfolio_capital_buckets, :portfolio_id)
      add_index :portfolio_capital_buckets, :portfolio_id, unique: true
    end
  end
end
