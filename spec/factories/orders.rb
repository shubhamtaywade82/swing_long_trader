# frozen_string_literal: true

FactoryBot.define do
  factory :order do
    instrument
    sequence(:client_order_id) { |n| "B-#{instrument.security_id}-#{Time.current.to_i.to_s[-6..]}-#{n}" }
    symbol { instrument.symbol_name }
    exchange_segment { instrument.exchange_segment }
    security_id { instrument.security_id }
    product_type { "EQUITY" }
    order_type { "MARKET" }
    transaction_type { "BUY" }
    quantity { 100 }
    price { nil }
    trigger_price { nil }
    validity { "DAY" }
    status { "pending" }
    dry_run { false }
    metadata { { placed_at: Time.current }.to_json }
    dhan_response { nil }
    error_message { nil }
  end

  trait :placed do
    status { "placed" }
    dhan_order_id { "DHAN_#{SecureRandom.hex(8)}" }
    dhan_response { { status: "success", orderId: dhan_order_id }.to_json }
  end

  trait :executed do
    status { "executed" }
    dhan_order_id { "DHAN_#{SecureRandom.hex(8)}" }
    exchange_order_id { "EXCH_#{SecureRandom.hex(8)}" }
    average_price { 100.0 }
    filled_quantity { quantity }
    pending_quantity { 0 }
    dhan_response { { status: "success", orderId: dhan_order_id }.to_json }
  end

  trait :rejected do
    status { "rejected" }
    error_message { "Order rejected by exchange" }
    dhan_response { { status: "error", message: error_message }.to_json }
  end

  trait :failed do
    status { "failed" }
    error_message { "Order placement failed" }
    dhan_response { { error: error_message }.to_json }
  end

  trait :dry_run do
    dry_run { true }
    status { "placed" }
    dhan_order_id { "DRY_RUN_#{id}" }
  end

  trait :limit_order do
    order_type { "LIMIT" }
    price { 100.0 }
  end

  trait :stop_loss_order do
    order_type { "SL" }
    trigger_price { 95.0 }
  end

  trait :sell_order do
    transaction_type { "SELL" }
    sequence(:client_order_id) { |n| "S-#{instrument.security_id}-#{Time.current.to_i.to_s[-6..]}-#{n}" }
  end
end
