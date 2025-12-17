# frozen_string_literal: true

class ConvertTimeframeToEnum < ActiveRecord::Migration[8.0]
  def up
    # Step 1: Add temporary integer column
    add_column :candle_series, :timeframe_enum, :integer, null: true

    # Step 2: Migrate existing string values to enum integers
    # daily = 0, weekly = 1, hourly = 2
    execute <<-SQL
      UPDATE candle_series
      SET timeframe_enum = CASE timeframe
        WHEN '1D' THEN 0
        WHEN '1W' THEN 1
        WHEN '1H' THEN 2
        WHEN '1h' THEN 2
        WHEN '60' THEN 2
        ELSE NULL
      END
    SQL

    # Step 3: Set default for any NULL values (shouldn't happen, but safety check)
    execute <<-SQL
      UPDATE candle_series
      SET timeframe_enum = 0
      WHERE timeframe_enum IS NULL
    SQL

    # Step 4: Make the column non-nullable
    change_column_null :candle_series, :timeframe_enum, false

    # Step 5: Remove old string column
    remove_column :candle_series, :timeframe

    # Step 6: Rename enum column to timeframe
    rename_column :candle_series, :timeframe_enum, :timeframe

    # Step 7: Recreate indexes (they should be recreated automatically, but ensure they exist)
    unless index_exists?(:candle_series, [:instrument_id, :timeframe, :timestamp],
                          name: "index_candle_series_on_instrument_timeframe_timestamp")
      add_index :candle_series, [:instrument_id, :timeframe, :timestamp],
                unique: true, name: "index_candle_series_on_instrument_timeframe_timestamp"
    end

    unless index_exists?(:candle_series, [:instrument_id, :timeframe])
      add_index :candle_series, [:instrument_id, :timeframe]
    end
  end

  def down
    # Step 1: Add back string column
    add_column :candle_series, :timeframe_string, :string, null: true

    # Step 2: Convert enum integers back to strings
    execute <<-SQL
      UPDATE candle_series
      SET timeframe_string = CASE timeframe
        WHEN 0 THEN '1D'
        WHEN 1 THEN '1W'
        WHEN 2 THEN '1H'
        ELSE '1D'
      END
    SQL

    # Step 3: Make column non-nullable
    change_column_null :candle_series, :timeframe_string, false

    # Step 4: Remove integer column
    remove_column :candle_series, :timeframe

    # Step 5: Rename string column back to timeframe
    rename_column :candle_series, :timeframe_string, :timeframe

    # Step 6: Recreate indexes
    unless index_exists?(:candle_series, [:instrument_id, :timeframe, :timestamp],
                          name: "index_candle_series_on_instrument_timeframe_timestamp")
      add_index :candle_series, [:instrument_id, :timeframe, :timestamp],
                unique: true, name: "index_candle_series_on_instrument_timeframe_timestamp"
    end

    unless index_exists?(:candle_series, [:instrument_id, :timeframe])
      add_index :candle_series, [:instrument_id, :timeframe]
    end
  end
end
