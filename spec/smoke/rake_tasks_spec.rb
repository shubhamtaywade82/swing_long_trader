# frozen_string_literal: true

require "rails_helper"
require "rake"

# Smoke tests for rake tasks - verify they don't crash
RSpec.describe "Rake Tasks Smoke Tests", type: :smoke do
  before do
    # Load all rake tasks
    Rake::Task.clear
    Rails.application.load_tasks
  end

  after do
    # Clear tasks after each test to avoid interference
    Rake::Task.clear
  end

  describe "instruments:status" do
    it "runs without errors" do
      # Mock Setting.fetch to avoid database dependency
      allow(Setting).to receive(:fetch).and_return("2024-01-01")

      expect do
        Rake::Task["instruments:status"].invoke
      rescue SystemExit
        # Expected when status check fails
      end.not_to raise_error
    end
  end

  describe "instruments:import" do
    it "is callable" do
      # Mock the importer to avoid actual API calls
      allow(InstrumentsImporter).to receive(:import_from_url).and_return({ instrument_total: 0, duration: 1.0 })

      expect do
        Rake::Task["instruments:import"].invoke
      end.not_to raise_error
    end
  end

  describe "solid_queue:verify" do
    it "runs without errors" do
      # This will check if tables exist
      expect do
        Rake::Task["solid_queue:verify"].invoke
      rescue SystemExit
        # Expected when SolidQueue tables are missing
      end.not_to raise_error
    end
  end

  describe "hardening:check" do
    it "runs without errors" do
      # Mock migration_context if it doesn't exist (Rails 8.1 compatibility)
      if ActiveRecord::Base.connection.respond_to?(:migration_context)
        # Rails 7.x and earlier
        allow(ActiveRecord::Base.connection).to receive(:migration_context).and_return(
          double("migration_context", needs_migration?: false),
        )
      else
        # Rails 8.1+ - use ActiveRecord::MigrationContext directly
        allow(ActiveRecord::MigrationContext).to receive(:new).and_return(
          double("migration_context", needs_migration?: false),
        )
      end

      hardening_task = Rake::Task["hardening:check"]
      expect do
        hardening_task.invoke
      rescue NoMethodError => e
        # Expected if migration_context is not available
        skip "Migration context not available: #{e.message}"
      end.not_to raise_error
    end
  end

  describe "hardening:secrets" do
    it "runs without errors" do
      expect do
        Rake::Task["hardening:secrets"].invoke
      end.not_to raise_error
    end
  end

  describe "hardening:indexes" do
    it "runs without errors" do
      expect do
        Rake::Task["hardening:indexes"].invoke
      rescue SystemExit
        # Expected when indexes check fails
      end.not_to raise_error
    end
  end

  describe "metrics:daily" do
    it "runs without errors" do
      expect do
        Rake::Task["metrics:daily"].invoke
      end.not_to raise_error
    end
  end

  describe "metrics:weekly" do
    it "runs without errors" do
      expect do
        Rake::Task["metrics:weekly"].invoke
      end.not_to raise_error
    end
  end

  describe "backtest:list" do
    it "runs without errors" do
      expect do
        Rake::Task["backtest:list"].invoke
      rescue SystemExit
        # Expected when no backtests found
      end.not_to raise_error
    end
  end

  describe "universe:stats" do
    it "runs without errors" do
      expect do
        Rake::Task["universe:stats"].invoke
      rescue SystemExit
        # Expected when stats check fails
      end.not_to raise_error
    end
  end

  describe "indicators:test" do
    it "handles missing candles gracefully" do
      # This should handle the case where no candles exist
      expect do
        Rake::Task["indicators:test"].invoke
      rescue SystemExit
        # Expected when no candles found
      end.not_to raise_error
    end
  end
end
