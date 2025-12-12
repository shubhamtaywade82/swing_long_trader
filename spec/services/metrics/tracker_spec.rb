# frozen_string_literal: true

require "rails_helper"

RSpec.describe Metrics::Tracker do
  let(:order) { create(:order) }

  before do
    Rails.cache.clear
    allow(Setting).to receive(:fetch_i).and_return(0)
    allow(Setting).to receive(:put)
  end

  describe ".track_order_placed" do
    it "increments order count for today" do
      allow(Setting).to receive(:fetch_i).with("orders.placed.2025-12-12", 0).and_return(5)

      described_class.track_order_placed(order)

      expect(Setting).to have_received(:put).with("orders.placed.2025-12-12", 6)
    end
  end

  describe ".track_order_failed" do
    it "increments failed order count" do
      allow(Setting).to receive(:fetch_i).with("orders.failed.2025-12-12", 0).and_return(2)

      described_class.track_order_failed(order)

      expect(Setting).to have_received(:put).with("orders.failed.2025-12-12", 3)
    end
  end

  describe ".track_dhan_api_call" do
    it "increments API call count" do
      # Mock cache since test environment uses null_store
      cache_store = {}
      allow(Rails.cache).to receive(:read) do |key|
        cache_store[key]
      end
      allow(Rails.cache).to receive(:write) do |key, value, _options = {}|
        cache_store[key] = value
      end

      described_class.track_dhan_api_call

      expect(cache_store["metrics:dhan_api_calls:2025-12-12"]).to eq(1)
    end
  end

  describe ".track_openai_api_call" do
    it "increments OpenAI API call count" do
      # Mock cache since test environment uses null_store
      cache_store = {}
      allow(Rails.cache).to receive(:read) do |key|
        cache_store[key]
      end
      allow(Rails.cache).to receive(:write) do |key, value, _options = {}|
        cache_store[key] = value
      end

      described_class.track_openai_api_call

      expect(cache_store["metrics:openai_api_calls:2025-12-12"]).to eq(1)
    end
  end

  describe ".track_openai_cost" do
    it "tracks OpenAI cost" do
      # Mock cache since test environment uses null_store
      cache_store = {}
      allow(Rails.cache).to receive(:read) do |key|
        cache_store[key]
      end
      allow(Rails.cache).to receive(:write) do |key, value, _options = {}|
        cache_store[key] = value
      end

      described_class.track_openai_cost(0.05)

      expect(cache_store["metrics:openai_cost:2025-12-12"]).to eq(0.05)
    end

    it "accumulates costs" do
      # Mock cache since test environment uses null_store
      cache_store = {}
      allow(Rails.cache).to receive(:read) do |key|
        cache_store[key]
      end
      allow(Rails.cache).to receive(:write) do |key, value, _options = {}|
        cache_store[key] = value
      end

      described_class.track_openai_cost(0.05)
      described_class.track_openai_cost(0.03)

      expect(cache_store["metrics:openai_cost:2025-12-12"]).to eq(0.08)
    end
  end

  describe ".get_daily_stats" do
    it "returns daily statistics" do
      # Mock cache since test environment uses null_store
      cache_store = {
        "metrics:dhan_api_calls:2025-12-12" => 10,
        "metrics:openai_api_calls:2025-12-12" => 5,
        "metrics:candidate_count:2025-12-12" => 20,
        "metrics:signal_count:2025-12-12" => 3,
      }
      allow(Rails.cache).to receive(:read) do |key|
        cache_store[key]
      end

      stats = described_class.get_daily_stats

      expect(stats[:dhan_api_calls]).to eq(10)
      expect(stats[:openai_api_calls]).to eq(5)
      expect(stats[:candidate_count]).to eq(20)
      expect(stats[:signal_count]).to eq(3)
    end

    it "returns 0 for missing metrics" do
      cache_store = {}
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }

      stats = described_class.get_daily_stats

      expect(stats[:dhan_api_calls]).to eq(0)
      expect(stats[:openai_api_calls]).to eq(0)
      expect(stats[:candidate_count]).to eq(0)
      expect(stats[:signal_count]).to eq(0)
    end

    it "includes failed jobs count" do
      cache_store = {
        "metrics:failed_jobs:Candles::DailyIngestorJob:2025-12-12" => 2,
        "metrics:failed_jobs:Screeners::SwingScreenerJob:2025-12-12" => 1,
      }
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }

      stats = described_class.get_daily_stats

      expect(stats[:failed_jobs]).to eq(3)
    end
  end

  describe ".get_orders_placed" do
    it "returns order count for today" do
      allow(Setting).to receive(:fetch_i).with("orders.placed.2025-12-12", 0).and_return(5)

      count = described_class.get_orders_placed

      expect(count).to eq(5)
    end

    it "returns order count for specific date" do
      date = 5.days.ago.to_date
      allow(Setting).to receive(:fetch_i).with("orders.placed.#{date.strftime('%Y-%m-%d')}", 0).and_return(3)

      count = described_class.get_orders_placed(date)

      expect(count).to eq(3)
    end
  end

  describe ".get_orders_failed" do
    it "returns failed order count for today" do
      allow(Setting).to receive(:fetch_i).with("orders.failed.2025-12-12", 0).and_return(2)

      count = described_class.get_orders_failed

      expect(count).to eq(2)
    end

    it "returns failed order count for specific date" do
      date = 3.days.ago.to_date
      allow(Setting).to receive(:fetch_i).with("orders.failed.#{date.strftime('%Y-%m-%d')}", 0).and_return(1)

      count = described_class.get_orders_failed(date)

      expect(count).to eq(1)
    end
  end

  describe ".get_openai_daily_cost" do
    it "returns cost for today" do
      cache_store = { "metrics:openai_cost:2025-12-12" => 0.15 }
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }

      cost = described_class.get_openai_daily_cost

      expect(cost).to eq(0.15)
    end

    it "returns 0.0 if no cost recorded" do
      cache_store = {}
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }

      cost = described_class.get_openai_daily_cost

      expect(cost).to eq(0.0)
    end

    it "returns cost for specific date" do
      date = 2.days.ago.to_date
      cache_store = { "metrics:openai_cost:#{date}" => 0.25 }
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }

      cost = described_class.get_openai_daily_cost(date)

      expect(cost).to eq(0.25)
    end
  end

  describe ".track_candidate_count" do
    it "stores candidate count" do
      cache_store = {}
      allow(Rails.cache).to receive(:write) { |key, value, _| cache_store[key] = value }

      described_class.track_candidate_count(15)

      expect(cache_store["metrics:candidate_count:2025-12-12"]).to eq(15)
    end
  end

  describe ".track_signal_count" do
    it "stores signal count" do
      cache_store = {}
      allow(Rails.cache).to receive(:write) { |key, value, _| cache_store[key] = value }

      described_class.track_signal_count(5)

      expect(cache_store["metrics:signal_count:2025-12-12"]).to eq(5)
    end
  end

  describe ".track_job_duration" do
    it "tracks job duration" do
      cache_store = {}
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }
      allow(Rails.cache).to receive(:write) { |key, value, _| cache_store[key] = value }

      described_class.track_job_duration("TestJob", 5.5)

      expect(cache_store["metrics:job_duration:TestJob:2025-12-12"]).to eq([5.5])
    end

    it "keeps only last 100 durations" do
      cache_store = {}
      durations = (1..100).to_a
      cache_store["metrics:job_duration:TestJob:2025-12-12"] = durations
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }
      allow(Rails.cache).to receive(:write) { |key, value, _| cache_store[key] = value }

      described_class.track_job_duration("TestJob", 101.0)

      stored = cache_store["metrics:job_duration:TestJob:2025-12-12"]
      expect(stored.size).to eq(100)
      expect(stored.last).to eq(101.0)
      expect(stored.first).to eq(2) # First element (1) was removed
    end
  end

  describe ".track_failed_job" do
    it "increments failed job count" do
      cache_store = {}
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }
      allow(Rails.cache).to receive(:write) { |key, value, _| cache_store[key] = value }

      described_class.track_failed_job("TestJob")

      expect(cache_store["metrics:failed_jobs:TestJob:2025-12-12"]).to eq(1)
    end

    it "accumulates failed job counts" do
      cache_store = { "metrics:failed_jobs:TestJob:2025-12-12" => 2 }
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }
      allow(Rails.cache).to receive(:write) { |key, value, _| cache_store[key] = value }

      described_class.track_failed_job("TestJob")

      expect(cache_store["metrics:failed_jobs:TestJob:2025-12-12"]).to eq(3)
    end
  end

  describe ".get_failed_jobs_count" do
    it "sums failed jobs for all tracked job types" do
      cache_store = {
        "metrics:failed_jobs:Candles::DailyIngestorJob:2025-12-12" => 2,
        "metrics:failed_jobs:Candles::WeeklyIngestorJob:2025-12-12" => 1,
        "metrics:failed_jobs:Screeners::SwingScreenerJob:2025-12-12" => 3,
      }
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }

      count = described_class.get_failed_jobs_count("2025-12-12")

      expect(count).to eq(6)
    end

    it "returns 0 if no failed jobs" do
      cache_store = {}
      allow(Rails.cache).to receive(:read) { |key| cache_store[key] }

      count = described_class.get_failed_jobs_count("2025-12-12")

      expect(count).to eq(0)
    end
  end
end
