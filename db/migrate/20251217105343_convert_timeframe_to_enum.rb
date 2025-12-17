# frozen_string_literal: true

class ConvertTimeframeToEnum < ActiveRecord::Migration[8.0]
  def up
    # Step 1: Add temporary integer column
    add_column :candle_series, :timeframe_enum, :integer, null: true

    # Step 2: Check for unknown timeframe values before migration
    unknown_result = execute(
      "SELECT DISTINCT timeframe FROM candle_series WHERE timeframe NOT IN ('1D', '1W', '1H', '1h', '60')"
    )
    
    # Handle different result formats (ActiveRecord::Result vs array)
    unknown_timeframes = if unknown_result.respond_to?(:to_a)
                           unknown_result.to_a
                         elsif unknown_result.is_a?(Array)
                           unknown_result
                         else
                           []
                         end

    if unknown_timeframes.any?
      unknown_values = unknown_timeframes.map { |row| row.is_a?(Array) ? row[0] : row['timeframe'] || row[:timeframe] }.compact.uniq
      if unknown_values.any?
        Rails.logger.warn(
          "[ConvertTimeframeToEnum] Found unknown timeframe values: #{unknown_values.inspect}. " \
          "These will be converted to daily (0)."
        )
      end
    end

    # Step 3: Migrate existing string values to enum integers
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

    # Step 4: Check for NULL values and log warning (shouldn't happen, but safety check)
    null_count_result = execute("SELECT COUNT(*) FROM candle_series WHERE timeframe_enum IS NULL")
    null_count = null_count_result.first[0] if null_count_result.respond_to?(:first)

    if null_count&.positive?
      Rails.logger.warn(
        "[ConvertTimeframeToEnum] Found #{null_count} records with NULL timeframe_enum. " \
        "These will be set to daily (0). Unknown timeframes may have been converted."
      )
      # Set default for any NULL values
      execute <<-SQL
        UPDATE candle_series
        SET timeframe_enum = 0
        WHERE timeframe_enum IS NULL
      SQL
    end

    # Step 5: Make the column non-nullable
    change_column_null :candle_series, :timeframe_enum, false

    # Step 6: Remove old string column
    remove_column :candle_series, :timeframe

    # Step 7: Rename enum column to timeframe
    rename_column :candle_series, :timeframe_enum, :timeframe

    # Step 8: Recreate indexes (they should be recreated automatically, but ensure they exist)
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
