# frozen_string_literal: true

class AddAtrBasedFieldsToPositions < ActiveRecord::Migration[8.0]
  def change
    add_column :positions, :tp1, :decimal, precision: 15, scale: 2, if_not_exists: true
    add_column :positions, :tp2, :decimal, precision: 15, scale: 2, if_not_exists: true
    add_column :positions, :atr, :decimal, precision: 15, scale: 2, if_not_exists: true
    add_column :positions, :atr_pct, :decimal, precision: 8, scale: 2, if_not_exists: true
    add_column :positions, :tp1_hit, :boolean, default: false, if_not_exists: true
    add_column :positions, :breakeven_stop, :decimal, precision: 15, scale: 2, if_not_exists: true
    add_column :positions, :atr_trailing_multiplier, :decimal, precision: 5, scale: 2, if_not_exists: true
    add_column :positions, :initial_stop_loss, :decimal, precision: 15, scale: 2, if_not_exists: true # Store original SL before breakeven

    # Add indexes for querying
    add_index :positions, :tp1_hit, if_not_exists: true unless index_exists?(:positions, :tp1_hit)
  end
end
