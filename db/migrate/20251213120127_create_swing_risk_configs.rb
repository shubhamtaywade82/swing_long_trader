# frozen_string_literal: true

class CreateSwingRiskConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :swing_risk_configs, if_not_exists: true do |t|
      t.references :portfolio, null: false, foreign_key: { to_table: :capital_allocation_portfolios }, index: true, unique: true
      t.decimal :risk_per_trade, precision: 5, scale: 2, default: 1.0, null: false # Percentage (0.5% - 1.0%)
      t.decimal :max_position_exposure, precision: 5, scale: 2, default: 15.0, null: false # Percentage (10% - 15%)
      t.integer :max_open_positions, default: 5, null: false # 3 - 5
      t.decimal :max_daily_risk, precision: 5, scale: 2, default: 2.0, null: false # Percentage
      t.decimal :max_portfolio_dd, precision: 5, scale: 2, default: 10.0, null: false # Percentage
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    unless index_exists?(:swing_risk_configs, :portfolio_id)
      add_index :swing_risk_configs, :portfolio_id, unique: true
    end
  end
end
