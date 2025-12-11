# frozen_string_literal: true

require 'test_helper'

class BacktestRunTest < ActiveSupport::TestCase
  test 'should be valid with valid attributes' do
    run = build(:backtest_run)
    assert run.valid?
  end

  test 'should require start_date' do
    run = build(:backtest_run, start_date: nil)
    assert_not run.valid?
    assert_includes run.errors[:start_date], "can't be blank"
  end

  test 'should require end_date' do
    run = build(:backtest_run, end_date: nil)
    assert_not run.valid?
    assert_includes run.errors[:end_date], "can't be blank"
  end

  test 'should require strategy_type' do
    run = build(:backtest_run, strategy_type: nil)
    assert_not run.valid?
    assert_includes run.errors[:strategy_type], "can't be blank"
  end

  test 'should require initial_capital' do
    run = build(:backtest_run, initial_capital: nil)
    assert_not run.valid?
    assert_includes run.errors[:initial_capital], "can't be blank"
  end

  test 'should require risk_per_trade' do
    run = build(:backtest_run, risk_per_trade: nil)
    assert_not run.valid?
    assert_includes run.errors[:risk_per_trade], "can't be blank"
  end

  test 'should validate strategy_type inclusion' do
    run = build(:backtest_run, strategy_type: 'invalid')
    assert_not run.valid?
    assert_includes run.errors[:strategy_type], 'is not included in the list'
  end

  test 'should validate status inclusion' do
    run = build(:backtest_run, status: 'invalid')
    assert_not run.valid?
    assert_includes run.errors[:status], 'is not included in the list'
  end

  test 'should have many backtest_positions' do
    run = create(:backtest_run)
    create_list(:backtest_position, 3, backtest_run: run)
    assert_equal 3, run.backtest_positions.count
  end

  test 'completed scope should return completed runs' do
    completed = create(:backtest_run, status: 'completed')
    pending = create(:backtest_run, status: 'pending')
    running = create(:backtest_run, status: 'running')

    completed_runs = BacktestRun.completed
    assert_includes completed_runs, completed
    assert_not_includes completed_runs, pending
    assert_not_includes completed_runs, running
  end

  test 'swing scope should return swing runs' do
    swing = create(:backtest_run, strategy_type: 'swing')
    long_term = create(:backtest_run, strategy_type: 'long_term')

    swing_runs = BacktestRun.swing
    assert_includes swing_runs, swing
    assert_not_includes swing_runs, long_term
  end

  test 'long_term scope should return long_term runs' do
    swing = create(:backtest_run, strategy_type: 'swing')
    long_term = create(:backtest_run, strategy_type: 'long_term')

    long_term_runs = BacktestRun.long_term
    assert_includes long_term_runs, long_term
    assert_not_includes long_term_runs, swing
  end

  test 'config_hash should parse JSON config' do
    config = { initial_capital: 100_000, risk_per_trade: 2.0 }
    run = create(:backtest_run, config: config.to_json)

    assert_equal config, run.config_hash
  end

  test 'config_hash should return empty hash for blank config' do
    run = create(:backtest_run, config: nil)
    assert_equal({}, run.config_hash)

    run.config = ''
    assert_equal({}, run.config_hash)
  end

  test 'config_hash should handle invalid JSON gracefully' do
    run = create(:backtest_run, config: 'invalid json')
    assert_equal({}, run.config_hash)
  end

  test 'results_hash should parse JSON results' do
    results = { total_return: 15.5, win_rate: 55.0 }
    run = create(:backtest_run, results: results.to_json)

    assert_equal results, run.results_hash
  end

  test 'results_hash should return empty hash for blank results' do
    run = create(:backtest_run, results: nil)
    assert_equal({}, run.results_hash)

    run.results = ''
    assert_equal({}, run.results_hash)
  end

  test 'results_hash should handle invalid JSON gracefully' do
    run = create(:backtest_run, results: 'invalid json')
    assert_equal({}, run.results_hash)
  end
end

