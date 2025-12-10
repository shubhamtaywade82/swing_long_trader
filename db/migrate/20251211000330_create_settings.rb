# frozen_string_literal: true

class CreateSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :settings, if_not_exists: true do |t|
      t.string :key, null: false
      t.text :value, null: true

      t.timestamps
    end

    unless index_exists?(:settings, :key)
      add_index :settings, :key, unique: true
    end
  end
end
