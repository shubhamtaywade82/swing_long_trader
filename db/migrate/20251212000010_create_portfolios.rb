# frozen_string_literal: true

class CreatePortfolios < ActiveRecord::Migration[8.0]
  def change
    create_table :portfolios, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :portfolio_type, null: false # live, paper
      t.date :date, null: false # Portfolio snapshot date
      
      # Capital and equity
      t.decimal :opening_capital, precision: 15, scale: 2, null: false
      t.decimal :closing_capital, precision: 15, scale: 2
      t.decimal :total_equity, precision: 15, scale: 2, null: false
      t.decimal :available_capital, precision: 15, scale: 2
      
      # P&L tracking
      t.decimal :realized_pnl, precision: 15, scale: 2, default: 0
      t.decimal :unrealized_pnl, precision: 15, scale: 2, default: 0
      t.decimal :total_pnl, precision: 15, scale: 2, default: 0
      t.decimal :pnl_pct, precision: 8, scale: 2, default: 0
      
      # Position metrics
      t.integer :open_positions_count, default: 0
      t.integer :closed_positions_count, default: 0
      t.integer :total_positions_count, default: 0
      t.decimal :total_exposure, precision: 15, scale: 2, default: 0
      t.decimal :utilization_pct, precision: 8, scale: 2, default: 0
      
      # Risk metrics
      t.decimal :max_drawdown, precision: 8, scale: 2, default: 0
      t.decimal :peak_equity, precision: 15, scale: 2
      t.decimal :win_rate, precision: 5, scale: 2
      t.decimal :avg_win, precision: 15, scale: 2
      t.decimal :avg_loss, precision: 15, scale: 2
      
      # Metadata
      t.text :metadata # JSON: positions summary, trades summary, etc.
      t.text :positions_summary # JSON: list of positions with details

      t.timestamps
    end

    unless index_exists?(:portfolios, [:portfolio_type, :date])
      add_index :portfolios, [:portfolio_type, :date], unique: true
    end

    unless index_exists?(:portfolios, :date)
      add_index :portfolios, :date
    end

    unless index_exists?(:portfolios, :portfolio_type)
      add_index :portfolios, :portfolio_type
    end
  end
end
