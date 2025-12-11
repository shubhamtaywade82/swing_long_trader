# frozen_string_literal: true

module Metrics
  # Tracks system metrics for observability
  class Tracker
    # Track order placement
    def self.track_order_placed(order)
      date = Date.today
      key = "orders.placed.#{date.strftime('%Y-%m-%d')}"
      current = Setting.fetch_i(key, 0)
      Setting.put(key, current + 1)
    end

    # Track order failure
    def self.track_order_failed(order)
      date = Date.today
      key = "orders.failed.#{date.strftime('%Y-%m-%d')}"
      current = Setting.fetch_i(key, 0)
      Setting.put(key, current + 1)
    end

    # Get order counts for a date
    def self.get_orders_placed(date = Date.today)
      key = "orders.placed.#{date.strftime('%Y-%m-%d')}"
      Setting.fetch_i(key, 0)
    end

    def self.get_orders_failed(date = Date.today)
      key = "orders.failed.#{date.strftime('%Y-%m-%d')}"
      Setting.fetch_i(key, 0)
    end
    def self.track_dhan_api_call
      today = Date.today.to_s
      key = "metrics:dhan_api_calls:#{today}"
      count = Rails.cache.read(key) || 0
      Rails.cache.write(key, count + 1, expires_in: 2.days)
    end

    def self.track_openai_api_call
      today = Date.today.to_s
      key = "metrics:openai_api_calls:#{today}"
      count = Rails.cache.read(key) || 0
      Rails.cache.write(key, count + 1, expires_in: 2.days)
    end

    def self.track_openai_cost(cost)
      today = Date.today.to_s
      key = "metrics:openai_cost:#{today}"
      total_cost = Rails.cache.read(key) || 0.0
      Rails.cache.write(key, total_cost + cost, expires_in: 2.days)
    end

    def self.get_openai_daily_cost(date = Date.today)
      date_str = date.to_s
      Rails.cache.read("metrics:openai_cost:#{date_str}") || 0.0
    end

    def self.track_candidate_count(count)
      today = Date.today.to_s
      key = "metrics:candidate_count:#{today}"
      Rails.cache.write(key, count, expires_in: 2.days)
    end

    def self.track_signal_count(count)
      today = Date.today.to_s
      key = "metrics:signal_count:#{today}"
      Rails.cache.write(key, count, expires_in: 2.days)
    end

    def self.track_job_duration(job_name, duration_seconds)
      today = Date.today.to_s
      key = "metrics:job_duration:#{job_name}:#{today}"
      durations = Rails.cache.read(key) || []
      durations << duration_seconds
      Rails.cache.write(key, durations.last(100), expires_in: 2.days) # Keep last 100
    end

    def self.track_failed_job(job_name)
      today = Date.today.to_s
      key = "metrics:failed_jobs:#{job_name}:#{today}"
      count = Rails.cache.read(key) || 0
      Rails.cache.write(key, count + 1, expires_in: 2.days)
    end

    def self.get_daily_stats(date = Date.today)
      date_str = date.to_s
      {
        dhan_api_calls: Rails.cache.read("metrics:dhan_api_calls:#{date_str}") || 0,
        openai_api_calls: Rails.cache.read("metrics:openai_api_calls:#{date_str}") || 0,
        candidate_count: Rails.cache.read("metrics:candidate_count:#{date_str}") || 0,
        signal_count: Rails.cache.read("metrics:signal_count:#{date_str}") || 0,
        failed_jobs: get_failed_jobs_count(date_str)
      }
    end

    def self.get_failed_jobs_count(date_str)
      # Get all failed job keys for the date
      # This is a simplified version - in production, query SolidQueue directly
      job_names = %w[Candles::DailyIngestorJob Candles::WeeklyIngestorJob Screeners::SwingScreenerJob]
      total = 0
      job_names.each do |job_name|
        count = Rails.cache.read("metrics:failed_jobs:#{job_name}:#{date_str}") || 0
        total += count
      end
      total
    end
  end
end


