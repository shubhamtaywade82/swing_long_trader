# frozen_string_literal: true

require 'test_helper'

class BacktestPositionTest < ActiveSupport::TestCase
  test 'should be valid with valid attributes' do
    position = build(:backtest_position)
    assert position.valid?
  end

  test 'should require entry_date' do
    position = build(:backtest_position, entry_date: nil)
    assert_not position.valid?
    assert_includes position.errors[:entry_date], "can't be blank"
  end

  test 'should require direction' do
    position = build(:backtest_position, direction: nil)
    assert_not position.valid?
    assert_includes position.errors[:direction], "can't be blank"
  end

  test 'should require entry_price' do
    position = build(:backtest_position, entry_price: nil)
    assert_not position.valid?
    assert_includes position.errors[:entry_price], "can't be blank"
  end

  test 'should require quantity' do
    position = build(:backtest_position, quantity: nil)
    assert_not position.valid?
    assert_includes position.errors[:quantity], "can't be blank"
  end

  test 'should validate direction inclusion' do
    position = build(:backtest_position, direction: 'invalid')
    assert_not position.valid?
    assert_includes position.errors[:direction], 'is not included in the list'
  end

  test 'should belong to backtest_run' do
    run = create(:backtest_run)
    position = create(:backtest_position, backtest_run: run)
    assert_equal run, position.backtest_run
  end

  test 'should belong to instrument' do
    instrument = create(:instrument)
    position = create(:backtest_position, instrument: instrument)
    assert_equal instrument, position.instrument
  end

  test 'long scope should return long positions' do
    long_pos = create(:backtest_position, direction: 'long')
    short_pos = create(:backtest_position, direction: 'short')

    long_positions = BacktestPosition.long
    assert_includes long_positions, long_pos
    assert_not_includes long_positions, short_pos
  end

  test 'short scope should return short positions' do
    long_pos = create(:backtest_position, direction: 'long')
    short_pos = create(:backtest_position, direction: 'short')

    short_positions = BacktestPosition.short
    assert_includes short_positions, short_pos
    assert_not_includes short_positions, long_pos
  end

  test 'closed scope should return closed positions' do
    closed = create(:backtest_position, exit_date: 1.day.ago)
    open_pos = create(:backtest_position, exit_date: nil)

    closed_positions = BacktestPosition.closed
    assert_includes closed_positions, closed
    assert_not_includes closed_positions, open_pos
  end

  test 'open scope should return open positions' do
    closed = create(:backtest_position, exit_date: 1.day.ago)
    open_pos = create(:backtest_position, exit_date: nil)

    open_positions = BacktestPosition.open
    assert_includes open_positions, open_pos
    assert_not_includes open_positions, closed
  end

  test 'closed? should return true when exit_date present' do
    position = create(:backtest_position, exit_date: 1.day.ago)
    assert position.closed?
  end

  test 'closed? should return false when exit_date nil' do
    position = create(:backtest_position, exit_date: nil)
    assert_not position.closed?
  end

  test 'open? should return true when exit_date nil' do
    position = create(:backtest_position, exit_date: nil)
    assert position.open?
  end

  test 'open? should return false when exit_date present' do
    position = create(:backtest_position, exit_date: 1.day.ago)
    assert_not position.open?
  end

  test 'calculate_pnl should return 0 for open positions' do
    position = create(:backtest_position, exit_date: nil)
    assert_equal 0, position.calculate_pnl
  end

  test 'calculate_pnl should calculate profit for long position' do
    position = create(:backtest_position, direction: 'long', entry_price: 100.0, exit_price: 110.0, quantity: 100)
    expected_pnl = (110.0 - 100.0) * 100
    assert_equal expected_pnl, position.calculate_pnl
  end

  test 'calculate_pnl should calculate profit for short position' do
    position = create(:backtest_position, direction: 'short', entry_price: 100.0, exit_price: 90.0, quantity: 100)
    expected_pnl = (100.0 - 90.0) * 100
    assert_equal expected_pnl, position.calculate_pnl
  end

  test 'calculate_pnl_pct should return 0 for open positions' do
    position = create(:backtest_position, exit_date: nil)
    assert_equal 0, position.calculate_pnl_pct
  end

  test 'calculate_pnl_pct should calculate percentage for long position' do
    position = create(:backtest_position, direction: 'long', entry_price: 100.0, exit_price: 110.0)
    expected_pct = ((110.0 - 100.0) / 100.0 * 100).round(4)
    assert_equal expected_pct, position.calculate_pnl_pct
  end

  test 'calculate_pnl_pct should calculate percentage for short position' do
    position = create(:backtest_position, direction: 'short', entry_price: 100.0, exit_price: 90.0)
    expected_pct = ((100.0 - 90.0) / 100.0 * 100).round(4)
    assert_equal expected_pct, position.calculate_pnl_pct
  end
end

