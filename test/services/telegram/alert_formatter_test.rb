# frozen_string_literal: true

require 'test_helper'

module Telegram
  class AlertFormatterTest < ActiveSupport::TestCase
    test 'should format daily candidates' do
      candidates = [
        { symbol: 'RELIANCE', score: 85.0, ai_score: 80.0 },
        { symbol: 'TCS', score: 82.0, ai_score: 75.0 }
      ]

      message = AlertFormatter.format_daily_candidates(candidates)

      assert_not_nil message
      assert_includes message, 'RELIANCE'
      assert_includes message, 'TCS'
    end

    test 'should format signal alert' do
      signal = {
        symbol: 'RELIANCE',
        direction: :long,
        entry_price: 2500.0,
        sl: 2400.0,
        tp: 2700.0,
        rr: 2.0,
        confidence: 85.0
      }

      message = AlertFormatter.format_signal_alert(signal)

      assert_not_nil message
      assert_includes message, 'RELIANCE'
      assert_includes message, 'LONG'
      assert_includes message, '2500'
    end

    test 'should format exit alert' do
      signal = {
        symbol: 'RELIANCE',
        direction: :long
      }

      message = AlertFormatter.format_exit_alert(
        signal,
        exit_reason: 'take_profit',
        exit_price: 2700.0,
        pnl: 10000.0
      )

      assert_not_nil message
      assert_includes message, 'RELIANCE'
      assert_includes message, 'take_profit'
      assert_includes message, '10000'
    end

    test 'should format error alert' do
      message = AlertFormatter.format_error_alert(
        'Test error message',
        context: 'TestContext'
      )

      assert_not_nil message
      assert_includes message, 'ERROR'
      assert_includes message, 'Test error message'
      assert_includes message, 'TestContext'
    end

    test 'should format portfolio snapshot' do
      portfolio_data = {
        total_value: 110000.0,
        total_pnl: 10000.0,
        total_pnl_pct: 10.0,
        positions: [
          { symbol: 'RELIANCE', pnl: 5000.0, pnl_pct: 5.0 }
        ]
      }

      message = AlertFormatter.format_portfolio_snapshot(portfolio_data)

      assert_not_nil message
      assert_includes message, '110000'
      assert_includes message, '10000'
      assert_includes message, 'RELIANCE'
    end

    test 'should handle empty candidates list' do
      message = AlertFormatter.format_daily_candidates([])

      assert_not_nil message
      assert_includes message.downcase, 'no candidates' || 'empty'
    end

    test 'should escape HTML in messages' do
      signal = {
        symbol: '<script>alert("xss")</script>',
        direction: :long,
        entry_price: 100.0,
        sl: 95.0,
        tp: 110.0,
        rr: 2.0,
        confidence: 80.0
      }

      message = AlertFormatter.format_signal_alert(signal)

      # Should not contain raw script tags
      assert_not_includes message, '<script>'
    end
  end
end

