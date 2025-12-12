# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Telegram::AlertFormatter, type: :service do
  describe '.format_daily_candidates' do
    it 'formats daily candidates' do
      candidates = [
        { symbol: 'RELIANCE', score: 85.0, ai_score: 80.0 },
        { symbol: 'TCS', score: 82.0, ai_score: 75.0 }
      ]

      message = described_class.format_daily_candidates(candidates)

      expect(message).not_to be_nil
      expect(message).to include('RELIANCE')
      expect(message).to include('TCS')
    end

    it 'handles empty candidates list' do
      message = described_class.format_daily_candidates([])

      expect(message).not_to be_nil
      expect(message.downcase).to match(/no candidates|empty/)
    end
  end

  describe '.format_signal_alert' do
    it 'formats signal alert' do
      signal = {
        symbol: 'RELIANCE',
        direction: :long,
        entry_price: 2500.0,
        sl: 2400.0,
        tp: 2700.0,
        rr: 2.0,
        confidence: 85.0
      }

      message = described_class.format_signal_alert(signal)

      expect(message).not_to be_nil
      expect(message).to include('RELIANCE')
      expect(message).to include('LONG')
      expect(message).to include('2500')
    end

    it 'escapes HTML in messages' do
      signal = {
        symbol: '<script>alert("xss")</script>',
        direction: :long,
        entry_price: 100.0,
        sl: 95.0,
        tp: 110.0,
        rr: 2.0,
        confidence: 80.0
      }

      message = described_class.format_signal_alert(signal)

      # Should not contain raw script tags
      expect(message).not_to include('<script>')
    end
  end

  describe '.format_exit_alert' do
    it 'formats exit alert' do
      signal = {
        symbol: 'RELIANCE',
        direction: :long
      }

      message = described_class.format_exit_alert(
        signal,
        exit_reason: 'take_profit',
        exit_price: 2700.0,
        pnl: 10000.0
      )

      expect(message).not_to be_nil
      expect(message).to include('RELIANCE')
      expect(message).to include('take_profit')
      expect(message).to include('10000')
    end
  end

  describe '.format_error_alert' do
    it 'formats error alert' do
      message = described_class.format_error_alert(
        'Test error message',
        context: 'TestContext'
      )

      expect(message).not_to be_nil
      expect(message).to include('Error Alert')
      expect(message).to include('Test error message')
      expect(message).to include('TestContext')
    end
  end

  describe '.format_portfolio_snapshot' do
    it 'formats portfolio snapshot' do
      portfolio_data = {
        total_value: 110000.0,
        total_pnl: 10000.0,
        total_pnl_pct: 10.0,
        positions: [
          { symbol: 'RELIANCE', pnl: 5000.0, pnl_pct: 5.0 }
        ]
      }

      message = described_class.format_portfolio_snapshot(portfolio_data)

      expect(message).not_to be_nil
      expect(message).to include('10000') # total_pnl
      expect(message).to include('RELIANCE')
    end
  end
end

