# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Metrics::Tracker do
  let(:order) { create(:order) }

  before do
    Rails.cache.clear
    allow(Setting).to receive(:fetch_i).and_return(0)
    allow(Setting).to receive(:put)
  end

  describe '.track_order_placed' do
    it 'increments order count for today' do
      allow(Setting).to receive(:fetch_i).with('orders.placed.2025-12-12', 0).and_return(5)

      described_class.track_order_placed(order)

      expect(Setting).to have_received(:put).with('orders.placed.2025-12-12', 6)
    end
  end

  describe '.track_order_failed' do
    it 'increments failed order count' do
      allow(Setting).to receive(:fetch_i).with('orders.failed.2025-12-12', 0).and_return(2)

      described_class.track_order_failed(order)

      expect(Setting).to have_received(:put).with('orders.failed.2025-12-12', 3)
    end
  end

  describe '.track_dhan_api_call' do
    it 'increments API call count' do
      described_class.track_dhan_api_call

      expect(Rails.cache.read('metrics:dhan_api_calls:2025-12-12')).to eq(1)
    end
  end

  describe '.track_openai_api_call' do
    it 'increments OpenAI API call count' do
      described_class.track_openai_api_call

      expect(Rails.cache.read('metrics:openai_api_calls:2025-12-12')).to eq(1)
    end
  end

  describe '.track_openai_cost' do
    it 'tracks OpenAI cost' do
      described_class.track_openai_cost(0.05)

      expect(Rails.cache.read('metrics:openai_cost:2025-12-12')).to eq(0.05)
    end

    it 'accumulates costs' do
      described_class.track_openai_cost(0.05)
      described_class.track_openai_cost(0.03)

      expect(Rails.cache.read('metrics:openai_cost:2025-12-12')).to eq(0.08)
    end
  end

  describe '.get_daily_stats' do
    it 'returns daily statistics' do
      Rails.cache.write('metrics:dhan_api_calls:2025-12-12', 10)
      Rails.cache.write('metrics:openai_api_calls:2025-12-12', 5)
      Rails.cache.write('metrics:candidate_count:2025-12-12', 20)
      Rails.cache.write('metrics:signal_count:2025-12-12', 3)

      stats = described_class.get_daily_stats

      expect(stats[:dhan_api_calls]).to eq(10)
      expect(stats[:openai_api_calls]).to eq(5)
      expect(stats[:candidate_count]).to eq(20)
      expect(stats[:signal_count]).to eq(3)
    end
  end
end

