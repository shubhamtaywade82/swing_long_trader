# frozen_string_literal: true

class CreatePaperLedgers < ActiveRecord::Migration[8.0]
  def change
    create_table :paper_ledgers, if_not_exists: true do |t|
      t.references :paper_portfolio, null: false, foreign_key: true
      t.references :paper_position, null: true, foreign_key: true
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.string :transaction_type, null: false # credit, debit
      t.string :reason, null: false # trade_entry, trade_exit, profit, loss, initial_capital, adjustment
      t.text :meta # JSON metadata
      t.text :description

      t.timestamps
    end

    unless index_exists?(:paper_ledgers, :paper_portfolio_id)
      add_index :paper_ledgers, :paper_portfolio_id
    end

    unless index_exists?(:paper_ledgers, :paper_position_id)
      add_index :paper_ledgers, :paper_position_id
    end

    unless index_exists?(:paper_ledgers, :reason)
      add_index :paper_ledgers, :reason
    end

    unless index_exists?(:paper_ledgers, [:paper_portfolio_id, :created_at])
      add_index :paper_ledgers, [:paper_portfolio_id, :created_at]
    end
  end
end
