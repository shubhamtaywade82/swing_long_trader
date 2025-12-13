# frozen_string_literal: true

class CreateSwingPositions < ActiveRecord::Migration[8.1]
  def change
    create_table :swing_positions, if_not_exists: true do |t|
      t.references :portfolio, null: false, foreign_key: { to_table: :capital_allocation_portfolios }, index: true
      t.references :instrument, null: false, foreign_key: { to_table: :instruments }, index: true
      t.decimal :entry_price, precision: 15, scale: 5, null: false
      t.decimal :current_price, precision: 15, scale: 5, null: false
      t.integer :quantity, null: false
      t.decimal :stop_loss, precision: 15, scale: 5
      t.decimal :take_profit, precision: 15, scale: 5
      t.string :status, default: "open", null: false # open | closed
      t.datetime :opened_at, null: false
      t.datetime :closed_at
      t.decimal :exit_price, precision: 15, scale: 5
      t.string :exit_reason
      t.decimal :realized_pnl, precision: 15, scale: 2, default: 0.0
      t.decimal :unrealized_pnl, precision: 15, scale: 2, default: 0.0
      t.text :metadata

      t.timestamps
    end

    unless index_exists?(:swing_positions, [:portfolio_id, :status])
      add_index :swing_positions, [:portfolio_id, :status]
    end

    unless index_exists?(:swing_positions, [:portfolio_id, :opened_at])
      add_index :swing_positions, [:portfolio_id, :opened_at]
    end

    unless index_exists?(:swing_positions, :status)
      add_index :swing_positions, :status
    end
  end
end
