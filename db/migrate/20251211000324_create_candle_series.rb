# frozen_string_literal: true

class CreateCandleSeries < ActiveRecord::Migration[8.0]
  def change
    create_table :candle_series, if_not_exists: true do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :timeframe, null: false # '1D', '1W', '15', '60', etc.
      t.datetime :timestamp, null: false
      t.decimal :open, precision: 15, scale: 5, null: false
      t.decimal :high, precision: 15, scale: 5, null: false
      t.decimal :low, precision: 15, scale: 5, null: false
      t.decimal :close, precision: 15, scale: 5, null: false
      t.bigint :volume, default: 0

      t.timestamps
    end

    unless index_exists?(:candle_series, [ :instrument_id, :timeframe, :timestamp ], name: 'index_candle_series_on_instrument_timeframe_timestamp')
      add_index :candle_series, [ :instrument_id, :timeframe, :timestamp ], unique: true, name: 'index_candle_series_on_instrument_timeframe_timestamp'
    end

    unless index_exists?(:candle_series, [ :instrument_id, :timeframe ])
      add_index :candle_series, [ :instrument_id, :timeframe ]
    end

    unless index_exists?(:candle_series, :timestamp)
      add_index :candle_series, :timestamp
    end
  end
end
