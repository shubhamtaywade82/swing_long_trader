# frozen_string_literal: true

class CreateCapitalAllocationPortfolios < ActiveRecord::Migration[8.1]
  def change
    create_table :capital_allocation_portfolios, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :mode, null: false, default: "paper" # paper | live
      t.decimal :total_equity, precision: 15, scale: 2, default: 0.0, null: false
      t.decimal :available_cash, precision: 15, scale: 2, default: 0.0, null: false
      t.decimal :swing_capital, precision: 15, scale: 2, default: 0.0, null: false
      t.decimal :long_term_capital, precision: 15, scale: 2, default: 0.0, null: false
      t.decimal :realized_pnl, precision: 15, scale: 2, default: 0.0, null: false
      t.decimal :unrealized_pnl, precision: 15, scale: 2, default: 0.0, null: false
      t.decimal :max_drawdown, precision: 10, scale: 2, default: 0.0, null: false
      t.decimal :peak_equity, precision: 15, scale: 2, default: 0.0, null: false
      t.text :metadata

      t.timestamps
    end

    unless index_exists?(:capital_allocation_portfolios, :name)
      add_index :capital_allocation_portfolios, :name, unique: true
    end

    unless index_exists?(:capital_allocation_portfolios, :mode)
      add_index :capital_allocation_portfolios, :mode
    end
  end
end
