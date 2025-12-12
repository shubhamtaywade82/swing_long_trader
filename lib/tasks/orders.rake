# frozen_string_literal: true

namespace :orders do
  desc "List orders pending approval"
  task pending_approval: :environment do
    orders = Order.pending_approval.order(created_at: :desc)

    if orders.empty?
      puts "✅ No orders pending approval"
    else
      puts "\n📋 Orders Pending Approval (#{orders.count}):\n\n"
      orders.each do |order|
        puts "  ID: #{order.id}"
        puts "  Symbol: #{order.symbol}"
        puts "  Type: #{order.transaction_type} #{order.order_type}"
        puts "  Quantity: #{order.quantity}"
        puts "  Price: ₹#{order.price}"
        puts "  Order ID: #{order.client_order_id}"
        puts "  Created: #{order.created_at}"
        puts "  ---"
      end
      puts "\nTo approve: rails orders:approve[ORDER_ID]"
      puts "To reject: rails orders:reject[ORDER_ID,reason]"
    end
  end

  desc "Approve an order"
  task :approve, %i[order_id approved_by] => :environment do |_t, args|
    order_id = args[:order_id]
    approved_by = args[:approved_by] || "manual"

    unless order_id
      puts "❌ Order ID required"
      puts "Usage: rails orders:approve[ORDER_ID,approved_by]"
      exit 1
    end

    result = Orders::Approval.approve(order_id, approved_by: approved_by)

    if result[:success]
      order = result[:order]
      puts "✅ Order approved: #{order.symbol} #{order.transaction_type} #{order.quantity}"
      puts "   Order ID: #{order.client_order_id}"
      puts "   Approved by: #{order.approved_by}"
      puts "\n⚠️  Note: Order still needs to be placed via executor"
    else
      puts "❌ Failed to approve order: #{result[:error]}"
      exit 1
    end
  end

  desc "Reject an order"
  task :reject, %i[order_id reason rejected_by] => :environment do |_t, args|
    order_id = args[:order_id]
    reason = args[:reason] || "Manual rejection"
    rejected_by = args[:rejected_by] || "manual"

    unless order_id
      puts "❌ Order ID required"
      puts "Usage: rails orders:reject[ORDER_ID,reason,rejected_by]"
      exit 1
    end

    result = Orders::Approval.reject(order_id, reason: reason, rejected_by: rejected_by)

    if result[:success]
      order = result[:order]
      puts "✅ Order rejected: #{order.symbol} #{order.transaction_type} #{order.quantity}"
      puts "   Order ID: #{order.client_order_id}"
      puts "   Rejected by: #{order.rejected_by}"
      puts "   Reason: #{order.rejection_reason}"
    else
      puts "❌ Failed to reject order: #{result[:error]}"
      exit 1
    end
  end

  desc "Show approval statistics"
  task stats: :environment do
    total = Order.real.count
    executed = Order.real.where(status: "executed").count
    pending_approval = Order.pending_approval.count
    approved = Order.approved.count
    rejected = Order.rejected.count
    approved_not_placed = Order.approved.where(status: "pending").count

    puts "\n📊 Order Approval Statistics:\n\n"
    puts "  Total orders: #{total}"
    puts "  Executed: #{executed}"
    puts "  Pending approval: #{pending_approval}"
    puts "  Approved: #{approved}"
    puts "  Approved (not yet placed): #{approved_not_placed}"
    puts "  Rejected: #{rejected}"
    puts "\n  Progress: #{executed}/30 trades executed (#{30 - executed} remaining for manual approval)"

    if approved_not_placed.positive?
      puts "\n  ⚠️  #{approved_not_placed} approved order(s) waiting to be placed"
      puts "     Run: rails orders:process_approved"
    end

    puts "\n"
  end

  desc "Process approved orders that are waiting to be placed"
  task process_approved: :environment do
    approved_orders = Order.approved.where(status: "pending").order(approved_at: :asc)

    if approved_orders.empty?
      puts "✅ No approved orders waiting to be placed"
      exit 0
    end

    puts "\n📋 Processing #{approved_orders.count} approved order(s)...\n\n"

    approved_orders.each do |order|
      puts "Processing order #{order.id}: #{order.symbol} #{order.transaction_type} #{order.quantity}"
      result = Orders::ProcessApprovedJob.new.perform(order_id: order.id)

      if result[:success]
        puts "  ✅ Order placed successfully"
      else
        puts "  ❌ Failed: #{result[:error]}"
      end
      puts
    end

    puts "✅ Processing complete\n\n"
  end
end
