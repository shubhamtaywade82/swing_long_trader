# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# Smoke tests for rake tasks - verify they don't crash
RSpec.describe 'Rake Tasks Smoke Tests', type: :smoke do
  before do
    # Load all rake tasks
    Rake::Task.clear
    Rails.application.load_tasks
  end

  after do
    # Clear tasks after each test to avoid interference
    Rake::Task.clear
  end

  describe 'instruments:status' do
    it 'should run without errors' do
      # Mock Setting.fetch to avoid database dependency
      allow(Setting).to receive(:fetch).and_return('2024-01-01')

      expect do
        begin
          Rake::Task['instruments:status'].invoke
        rescue SystemExit
          # Expected when status check fails
        end
      end.not_to raise_error
    end
  end

  describe 'instruments:import' do
    it 'should be callable' do
      # Mock the importer to avoid actual API calls
      allow(InstrumentsImporter).to receive(:import_from_url).and_return({ instrument_total: 0, duration: 1.0 })

      expect do
        Rake::Task['instruments:import'].invoke
      end.not_to raise_error
    end
  end

  describe 'solid_queue:verify' do
    it 'should run without errors' do
      # This will check if tables exist
      expect do
        Rake::Task['solid_queue:verify'].invoke
      end.not_to raise_error
    end
  end

  describe 'hardening:check' do
    it 'should run without errors' do
      # Mock all the check methods
      hardening_task = Rake::Task['hardening:check']
      expect do
        hardening_task.invoke
      end.not_to raise_error
    end
  end

  describe 'hardening:secrets' do
    it 'should run without errors' do
      expect do
        Rake::Task['hardening:secrets'].invoke
      end.not_to raise_error
    end
  end

  describe 'hardening:indexes' do
    it 'should run without errors' do
      expect do
        Rake::Task['hardening:indexes'].invoke
      end.not_to raise_error
    end
  end

  describe 'metrics:daily' do
    it 'should run without errors' do
      expect do
        Rake::Task['metrics:daily'].invoke
      end.not_to raise_error
    end
  end

  describe 'metrics:weekly' do
    it 'should run without errors' do
      expect do
        Rake::Task['metrics:weekly'].invoke
      end.not_to raise_error
    end
  end

  describe 'backtest:list' do
    it 'should run without errors' do
      expect do
        Rake::Task['backtest:list'].invoke
      end.not_to raise_error
    end
  end

  describe 'universe:stats' do
    it 'should run without errors' do
      expect do
        Rake::Task['universe:stats'].invoke
      end.not_to raise_error
    end
  end

  describe 'indicators:test' do
    it 'should handle missing candles gracefully' do
      # This should handle the case where no candles exist
      expect do
        begin
          Rake::Task['indicators:test'].invoke
        rescue SystemExit
          # Expected when no candles found
        end
      end.not_to raise_error
    end
  end
end

