# frozen_string_literal: true

class FixInstrumentsUniqueIndex < ActiveRecord::Migration[8.0]
  def up
    # Remove incorrect unique index on security_id alone
    if index_exists?(:instruments, :security_id, name: 'index_instruments_on_security_id')
      remove_index :instruments, name: 'index_instruments_on_security_id'
    end

    # Remove old composite unique index that includes symbol_name
    if index_exists?(:instruments, [ :security_id, :symbol_name, :exchange, :segment ], name: 'index_instruments_unique')
      remove_index :instruments, name: 'index_instruments_unique'
    end

    # Add non-unique index on security_id for performance (no longer unique)
    unless index_exists?(:instruments, :security_id)
      add_index :instruments, :security_id
    end

    # Add correct unique index on (security_id, exchange, segment)
    unless index_exists?(:instruments, [ :security_id, :exchange, :segment ], name: 'index_instruments_unique')
      add_index :instruments, [ :security_id, :exchange, :segment ], unique: true, name: 'index_instruments_unique'
    end
  end

  def down
    # Restore old indexes
    if index_exists?(:instruments, [ :security_id, :exchange, :segment ], name: 'index_instruments_unique')
      remove_index :instruments, name: 'index_instruments_unique'
    end

    if index_exists?(:instruments, :security_id)
      remove_index :instruments, :security_id
    end

    # Restore unique index on security_id alone
    unless index_exists?(:instruments, :security_id, name: 'index_instruments_on_security_id')
      add_index :instruments, :security_id, unique: true, name: 'index_instruments_on_security_id'
    end

    # Restore old composite unique index
    unless index_exists?(:instruments, [ :security_id, :symbol_name, :exchange, :segment ], name: 'index_instruments_unique')
      add_index :instruments, [ :security_id, :symbol_name, :exchange, :segment ], unique: true, name: 'index_instruments_unique'
    end
  end
end

