# frozen_string_literal: true

class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders, if_not_exists: true do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :dhan_order_id # DhanHQ order ID
      t.string :client_order_id, null: false # Our internal order ID (for idempotency)
      t.string :symbol, null: false
      t.string :exchange_segment, null: false
      t.string :security_id, null: false
      t.string :product_type, null: false # EQUITY, MARGIN, etc.
      t.string :order_type, null: false # MARKET, LIMIT, SL, SL-M
      t.string :transaction_type, null: false # BUY, SELL
      t.decimal :price, precision: 15, scale: 2 # Limit price (for LIMIT orders)
      t.decimal :trigger_price, precision: 15, scale: 2 # Stop loss trigger price
      t.integer :quantity, null: false
      t.decimal :disclosed_quantity, precision: 15, scale: 2, default: 0
      t.string :validity, default: 'DAY' # DAY, IOC, etc.
      t.string :status, default: 'pending' # pending, placed, executed, rejected, cancelled, failed
      t.text :dhan_response # JSON response from DhanHQ
      t.text :error_message
      t.string :exchange_order_id # Exchange order ID (after placement)
      t.decimal :average_price, precision: 15, scale: 2 # Average execution price
      t.integer :filled_quantity, default: 0
      t.integer :pending_quantity, default: 0
      t.integer :cancelled_quantity, default: 0
      t.boolean :dry_run, default: false # Whether this was a dry-run order
      t.text :metadata # JSON metadata (signal info, risk checks, etc.)

      t.timestamps
    end

    unless index_exists?(:orders, :client_order_id)
      add_index :orders, :client_order_id, unique: true
    end

    unless index_exists?(:orders, :dhan_order_id)
      add_index :orders, :dhan_order_id
    end

    unless index_exists?(:orders, :status)
      add_index :orders, :status
    end

    unless index_exists?(:orders, :instrument_id)
      add_index :orders, :instrument_id
    end

    unless index_exists?(:orders, [:status, :created_at])
      add_index :orders, [:status, :created_at]
    end
  end
end
