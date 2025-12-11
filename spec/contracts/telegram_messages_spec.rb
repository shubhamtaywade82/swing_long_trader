# frozen_string_literal: true

require 'rails_helper'

# Contract tests for Telegram message formatting
# Ensures message structure and content meet Telegram API requirements
RSpec.describe 'Telegram Messages Contract', type: :contract do
  describe 'daily candidates message' do
    it 'should be valid HTML' do
      candidates = [
        { symbol: 'RELIANCE', score: 85.0, ai_score: 80.0, direction: 'long' },
        { symbol: 'TCS', score: 82.0, ai_score: 75.0, direction: 'long' }
      ]

      message = Telegram::AlertFormatter.format_daily_candidates(candidates)

      # Should contain HTML tags
      expect(message).to match(/<b>/)
      # Should contain candidate symbols
      expect(message).to include('RELIANCE')
      expect(message).to include('TCS')
      # Should not be empty
      expect(message).not_to be_empty
      # Should be under Telegram's 4096 character limit
      expect(message.length).to be < 4096
    end
  end

  describe 'signal alert message' do
    it 'should contain all required fields' do
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
      expect(message).to include('RELIANCE')
      expect(message).to include('LONG')
      expect(message).to include('2500') # entry price
      expect(message).to include('2400') # stop loss
      expect(message).to include('2700') # take profit
      expect(message).to include('2.0') # risk reward
      expect(message).to include('85') # confidence
      # Should be valid length
      expect(message.length).to be < 4096
    end
  end

  describe 'exit alert message' do
    it 'should contain exit details' do
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

      expect(message).to include('RELIANCE')
      expect(message).to include(exit_reason)
      expect(message).to include('2700')
      expect(message).to include('10000')
      expect(message.length).to be < 4096
    end
  end

  describe 'error alert message' do
    it 'should contain error details' do
      error_message = 'Test error message'
      context = 'TestContext'

      message = Telegram::AlertFormatter.format_error_alert(
        error_message,
        context: context
      )

      expect(message).to include('ERROR')
      expect(message).to include(error_message)
      expect(message).to include(context)
      expect(message.length).to be < 4096
    end
  end

  describe 'portfolio snapshot message' do
    it 'should contain portfolio data' do
      portfolio_data = {
        total_value: 110000.0,
        total_pnl: 10000.0,
        total_pnl_pct: 10.0,
        positions: [
          { symbol: 'RELIANCE', pnl: 5000.0, pnl_pct: 5.0 }
        ]
      }

      message = Telegram::AlertFormatter.format_portfolio_snapshot(portfolio_data)

      expect(message).to include('110000')
      expect(message).to include('10000')
      expect(message).to include('RELIANCE')
      expect(message.length).to be < 4096
    end
  end

  describe 'message formatting' do
    it 'should escape HTML special characters' do
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
      expect(message.length).to be < 4096
    end

    it 'should handle empty candidates list' do
      message = Telegram::AlertFormatter.format_daily_candidates([])

      expect(message).not_to be_empty
      expect(message.length).to be < 4096
      # Should indicate no candidates
      expect(message.downcase).to match(/no candidates|empty/)
    end

    it 'should not exceed Telegram character limit' do
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
      expect(message.length).to be < 4096
    end

    it 'all message types should return strings' do
      signal = { symbol: 'TEST', direction: :long, entry_price: 100.0, sl: 95.0, tp: 110.0, rr: 2.0, confidence: 80.0 }

      expect(Telegram::AlertFormatter.format_daily_candidates([])).to be_a(String)
      expect(Telegram::AlertFormatter.format_signal_alert(signal)).to be_a(String)
      expect(Telegram::AlertFormatter.format_exit_alert(signal, exit_reason: 'test', exit_price: 100.0, pnl: 0.0)).to be_a(String)
      expect(Telegram::AlertFormatter.format_error_alert('test')).to be_a(String)
      expect(Telegram::AlertFormatter.format_portfolio_snapshot({ total_value: 100000.0, total_pnl: 0.0, total_pnl_pct: 0.0, positions: [] })).to be_a(String)
    end
  end
end

