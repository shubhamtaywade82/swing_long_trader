# frozen_string_literal: true

class CreatePaperPortfolios < ActiveRecord::Migration[8.0]
  def change
    create_table :paper_portfolios, if_not_exists: true do |t|
      t.string :name, null: false
      t.decimal :capital, precision: 15, scale: 2, null: false, default: 0
      t.decimal :reserved_capital, precision: 15, scale: 2, default: 0
      t.decimal :available_capital, precision: 15, scale: 2, default: 0
      t.decimal :total_equity, precision: 15, scale: 2, default: 0
      t.decimal :pnl_realized, precision: 15, scale: 2, default: 0
      t.decimal :pnl_unrealized, precision: 15, scale: 2, default: 0
      t.decimal :max_drawdown, precision: 15, scale: 2, default: 0
      t.decimal :peak_equity, precision: 15, scale: 2, default: 0
      t.text :metadata # JSON metadata for additional fields

      t.timestamps
    end

    unless index_exists?(:paper_portfolios, :name)
      add_index :paper_portfolios, :name, unique: true
    end
  end
end
