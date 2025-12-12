# frozen_string_literal: true

class AddPortfolioFieldsToPositions < ActiveRecord::Migration[8.0]
  def change
    # Add STI type column for Portfolio
    add_column :positions, :type, :string unless column_exists?(:positions, :type)
    add_index :positions, :type unless index_exists?(:positions, :type)

    # Add portfolio snapshot date for grouping positions
    add_column :positions, :portfolio_date, :date unless column_exists?(:positions, :portfolio_date)
    add_index :positions, :portfolio_date unless index_exists?(:positions, :portfolio_date)
    add_index :positions, [:type, :portfolio_date] unless index_exists?(:positions, [:type, :portfolio_date])

    # Add portfolio aggregation fields (for Portfolio type records)
    add_column :positions, :portfolio_type, :string unless column_exists?(:positions, :portfolio_type) # live, paper
    add_column :positions, :opening_capital, :decimal, precision: 15, scale: 2 unless column_exists?(:positions, :opening_capital)
    add_column :positions, :closing_capital, :decimal, precision: 15, scale: 2 unless column_exists?(:positions, :closing_capital)
    add_column :positions, :total_equity, :decimal, precision: 15, scale: 2 unless column_exists?(:positions, :total_equity)
    add_column :positions, :available_capital, :decimal, precision: 15, scale: 2 unless column_exists?(:positions, :available_capital)
    add_column :positions, :total_exposure, :decimal, precision: 15, scale: 2 unless column_exists?(:positions, :total_exposure)
    add_column :positions, :open_positions_count, :integer, default: 0 unless column_exists?(:positions, :open_positions_count)
    add_column :positions, :closed_positions_count, :integer, default: 0 unless column_exists?(:positions, :closed_positions_count)
    add_column :positions, :utilization_pct, :decimal, precision: 8, scale: 2, default: 0 unless column_exists?(:positions, :utilization_pct)
    add_column :positions, :win_rate, :decimal, precision: 5, scale: 2 unless column_exists?(:positions, :win_rate)
    add_column :positions, :peak_equity, :decimal, precision: 15, scale: 2 unless column_exists?(:positions, :peak_equity)
    
    # Add flag to mark positions that continue from previous day
    add_column :positions, :continued_from_previous_day, :boolean, default: false unless column_exists?(:positions, :continued_from_previous_day)
    add_index :positions, :continued_from_previous_day unless index_exists?(:positions, :continued_from_previous_day)
  end
end
