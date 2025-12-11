# frozen_string_literal: true

class AddApprovalFieldsToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :requires_approval, :boolean, default: false, if_not_exists: true
    add_column :orders, :approved_at, :datetime, if_not_exists: true
    add_column :orders, :approved_by, :string, if_not_exists: true
    add_column :orders, :rejected_at, :datetime, if_not_exists: true
    add_column :orders, :rejected_by, :string, if_not_exists: true
    add_column :orders, :rejection_reason, :text, if_not_exists: true

    unless index_exists?(:orders, :requires_approval)
      add_index :orders, :requires_approval
    end
  end
end
