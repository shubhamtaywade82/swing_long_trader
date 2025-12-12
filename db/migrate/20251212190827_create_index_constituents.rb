# frozen_string_literal: true

class CreateIndexConstituents < ActiveRecord::Migration[8.1]
  def change
    create_table :index_constituents, if_not_exists: true do |t|
      t.string :company_name, null: false
      t.string :industry
      t.string :symbol, null: false
      t.string :series
      t.string :isin_code
      t.string :index_name, null: false

      t.timestamps
    end

    # Indexes for efficient querying
    unless index_exists?(:index_constituents, :symbol)
      add_index :index_constituents, :symbol
    end

    unless index_exists?(:index_constituents, :isin_code)
      add_index :index_constituents, :isin_code, where: "isin_code IS NOT NULL"
    end

    unless index_exists?(:index_constituents, :index_name)
      add_index :index_constituents, :index_name
    end

    # Unique constraint: same symbol+isin+index should only appear once
    unless index_exists?(:index_constituents, [:symbol, :isin_code, :index_name], name: "index_index_constituents_unique")
      add_index :index_constituents, [:symbol, :isin_code, :index_name],
                unique: true,
                name: "index_index_constituents_unique"
    end

    # Index for industry filtering
    unless index_exists?(:index_constituents, :industry)
      add_index :index_constituents, :industry
    end
  end
end
