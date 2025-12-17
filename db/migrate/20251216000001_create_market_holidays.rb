# frozen_string_literal: true

class CreateMarketHolidays < ActiveRecord::Migration[8.0]
  def change
    create_table :market_holidays do |t|
      t.date :date, null: false
      t.string :description, null: false
      t.integer :year, null: false

      t.timestamps
    end

    unless index_exists?(:market_holidays, :date)
      add_index :market_holidays, :date, unique: true
    end

    unless index_exists?(:market_holidays, :year)
      add_index :market_holidays, :year
    end
  end
end
