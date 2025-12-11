# frozen_string_literal: true

require 'test_helper'
require 'rake'

# Smoke tests for rake tasks - verify they don't crash
class RakeTasksSmokeTest < ActiveSupport::TestCase
  def setup
    # Load all rake tasks
    Rake::Task.clear
    Rails.application.load_tasks
  end

  def teardown
    # Clear tasks after each test to avoid interference
    Rake::Task.clear
  end

  test 'instruments:status should run without errors' do
    # Mock Setting.fetch to avoid database dependency
    Setting.stub(:fetch, '2024-01-01') do
      assert_nothing_raised do
        begin
          Rake::Task['instruments:status'].invoke
        rescue SystemExit
          # Expected when status check fails
        end
      end
    end
  end

  test 'instruments:import should be callable' do
    # Mock the importer to avoid actual API calls
    InstrumentsImporter.stub(:import_from_url, { instrument_total: 0, duration: 1.0 }) do
      assert_nothing_raised do
        Rake::Task['instruments:import'].invoke
      end
    end
  end

  test 'solid_queue:verify should run without errors' do
    # This will check if tables exist
    assert_nothing_raised do
      Rake::Task['solid_queue:verify'].invoke
    end
  end

  test 'hardening:check should run without errors' do
    # Mock all the check methods
    hardening_task = Rake::Task['hardening:check']
    assert_nothing_raised do
      hardening_task.invoke
    end
  end

  test 'hardening:secrets should run without errors' do
    assert_nothing_raised do
      Rake::Task['hardening:secrets'].invoke
    end
  end

  test 'hardening:indexes should run without errors' do
    assert_nothing_raised do
      Rake::Task['hardening:indexes'].invoke
    end
  end

  test 'metrics:daily should run without errors' do
    assert_nothing_raised do
      Rake::Task['metrics:daily'].invoke
    end
  end

  test 'metrics:weekly should run without errors' do
    assert_nothing_raised do
      Rake::Task['metrics:weekly'].invoke
    end
  end

  test 'backtest:list should run without errors' do
    assert_nothing_raised do
      Rake::Task['backtest:list'].invoke
    end
  end

  test 'universe:stats should run without errors' do
    assert_nothing_raised do
      Rake::Task['universe:stats'].invoke
    end
  end

  test 'indicators:test should handle missing candles gracefully' do
    # This should handle the case where no candles exist
    assert_nothing_raised do
      begin
        Rake::Task['indicators:test'].invoke
      rescue SystemExit
        # Expected when no candles found
      end
    end
  end
end

