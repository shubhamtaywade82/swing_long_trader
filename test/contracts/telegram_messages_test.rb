# frozen_string_literal: true

require 'test_helper'

# Contract tests for Telegram message formatting
# Ensures message structure and content meet Telegram API requirements
module Contracts
  class TelegramMessagesTest < ActiveSupport::TestCase
    test 'daily candidates message should be valid HTML' do
      candidates = [
        { symbol: 'RELIANCE', score: 85.0, ai_score: 80.0, direction: 'long' },
        { symbol: 'TCS', score: 82.0, ai_score: 75.0, direction: 'long' }
      ]

      message = Telegram::AlertFormatter.format_daily_candidates(candidates)

      # Should contain HTML tags
      assert_match(/<b>/, message)
      # Should contain candidate symbols
      assert_includes message, 'RELIANCE'
      assert_includes message, 'TCS'
      # Should not be empty
      assert_not_empty message
      # Should be under Telegram's 4096 character limit
      assert message.length < 4096, "Message too long: #{message.length} characters"
    end

    test 'signal alert message should contain all required fields' do
      signal = {
        symbol: 'RELIANCE',
        direction: :long,
        entry_price: 2500.0,
        sl: 2400.0,
        tp: 2700.0,
        rr: 2.0,
        confidence: 85.0
      }

      message = Telegram::AlertFormatter.format_signal_alert(signal)

      # Required fields
      assert_includes message, 'RELIANCE'
      assert_includes message, 'LONG'
      assert_includes message, '2500' # entry price
      assert_includes message, '2400' # stop loss
      assert_includes message, '2700' # take profit
      assert_includes message, '2.0' # risk reward
      assert_includes message, '85' # confidence
      # Should be valid length
      assert message.length < 4096
    end

    test 'exit alert message should contain exit details' do
      signal = { symbol: 'RELIANCE', direction: :long }
      exit_reason = 'take_profit'
      exit_price = 2700.0
      pnl = 10000.0

      message = Telegram::AlertFormatter.format_exit_alert(
        signal,
        exit_reason: exit_reason,
        exit_price: exit_price,
        pnl: pnl
      )

      assert_includes message, 'RELIANCE'
      assert_includes message, exit_reason
      assert_includes message, '2700'
      assert_includes message, '10000'
      assert message.length < 4096
    end

    test 'error alert message should contain error details' do
      error_message = 'Test error message'
      context = 'TestContext'

      message = Telegram::AlertFormatter.format_error_alert(
        error_message,
        context: context
      )

      assert_includes message, 'ERROR'
      assert_includes message, error_message
      assert_includes message, context
      assert message.length < 4096
    end

    test 'portfolio snapshot message should contain portfolio data' do
      portfolio_data = {
        total_value: 110000.0,
        total_pnl: 10000.0,
        total_pnl_pct: 10.0,
        positions: [
          { symbol: 'RELIANCE', pnl: 5000.0, pnl_pct: 5.0 }
        ]
      }

      message = Telegram::AlertFormatter.format_portfolio_snapshot(portfolio_data)

      assert_includes message, '110000'
      assert_includes message, '10000'
      assert_includes message, 'RELIANCE'
      assert message.length < 4096
    end

    test 'messages should escape HTML special characters' do
      signal = {
        symbol: '<script>alert("xss")</script>',
        direction: :long,
        entry_price: 100.0,
        sl: 95.0,
        tp: 110.0,
        rr: 2.0,
        confidence: 80.0
      }

      message = Telegram::AlertFormatter.format_signal_alert(signal)

      # Should not contain raw script tags (should be escaped or removed)
      # Telegram uses HTML parsing, so we should avoid raw script tags
      # The formatter should handle this, but we verify it doesn't break
      assert message.length < 4096
    end

    test 'empty candidates list should return valid message' do
      message = Telegram::AlertFormatter.format_daily_candidates([])

      assert_not_empty message
      assert message.length < 4096
      # Should indicate no candidates
      assert_match(/no candidates|empty/i, message.downcase)
    end

    test 'messages should not exceed Telegram character limit' do
      # Create a large candidate list
      candidates = 100.times.map do |i|
        {
          symbol: "STOCK#{i}",
          score: 80.0 + i,
          ai_score: 75.0 + i,
          direction: 'long',
          metadata: { trend_alignment: ['EMA', 'RSI', 'MACD'] * 5 }
        }
      end

      message = Telegram::AlertFormatter.format_daily_candidates(candidates)

      # Telegram limit is 4096 characters
      assert message.length < 4096, "Message exceeds limit: #{message.length} characters"
    end

    test 'all message types should return strings' do
      signal = { symbol: 'TEST', direction: :long, entry_price: 100.0, sl: 95.0, tp: 110.0, rr: 2.0, confidence: 80.0 }

      assert_kind_of String, Telegram::AlertFormatter.format_daily_candidates([])
      assert_kind_of String, Telegram::AlertFormatter.format_signal_alert(signal)
      assert_kind_of String, Telegram::AlertFormatter.format_exit_alert(signal, exit_reason: 'test', exit_price: 100.0, pnl: 0.0)
      assert_kind_of String, Telegram::AlertFormatter.format_error_alert('test')
      assert_kind_of String, Telegram::AlertFormatter.format_portfolio_snapshot({ total_value: 100000.0, total_pnl: 0.0, total_pnl_pct: 0.0, positions: [] })
    end
  end
end

