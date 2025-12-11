# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Telegram Notifier Integration', type: :integration do
  let(:chat_id) { ENV['TELEGRAM_CHAT_ID'] || '123456789' }
  let(:bot_token) { ENV['TELEGRAM_BOT_TOKEN'] || 'test_bot_token' }

  before do
    # Set test environment variables
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('TELEGRAM_BOT_TOKEN').and_return(bot_token)
    allow(ENV).to receive(:[]).with('TELEGRAM_CHAT_ID').and_return(chat_id)
  end

  describe 'End-to-End Telegram Message Sending', :vcr do
    context 'when sending daily candidates message' do
      let(:candidates) do
        [
          {
            symbol: 'RELIANCE',
            score: 85.0,
            ai_score: 80.0,
            direction: 'long',
            instrument_id: 1,
            indicators: { rsi: 65, ema20: 2500.0 }
          },
          {
            symbol: 'TCS',
            score: 82.0,
            ai_score: 75.0,
            direction: 'long',
            instrument_id: 2,
            indicators: { rsi: 60, ema20: 3200.0 }
          }
        ]
      end

      it 'sends formatted message to Telegram API' do
        # Mock TelegramNotifier
        allow(::TelegramNotifier).to receive(:enabled?).and_return(true)
        allow(::TelegramNotifier).to receive(:send_message).and_return(true)

        result = Telegram::Notifier.send_daily_candidates(candidates)

        expect(::TelegramNotifier).to have_received(:send_message).with(
          anything,
          parse_mode: 'HTML'
        )
      end

      it 'handles API errors gracefully' do
        # Mock TelegramNotifier to raise error
        allow(::TelegramNotifier).to receive(:enabled?).and_return(true)
        allow(::TelegramNotifier).to receive(:send_message).and_raise(StandardError.new('API Error'))

        expect do
          Telegram::Notifier.send_daily_candidates(candidates)
        end.not_to raise_error
      end
    end

    context 'when sending signal alert' do
      let(:signal) do
        {
          symbol: 'RELIANCE',
          direction: :long,
          entry_price: 2500.0,
          sl: 2400.0,
          tp: 2700.0,
          rr: 2.0,
          confidence: 85.0,
          qty: 10,
          holding_days_estimate: 5
        }
      end

      it 'sends signal alert to Telegram' do
        allow(::TelegramNotifier).to receive(:enabled?).and_return(true)
        allow(::TelegramNotifier).to receive(:send_message).and_return(true)

        Telegram::Notifier.send_signal_alert(signal)

        expect(::TelegramNotifier).to have_received(:send_message).with(
          anything,
          parse_mode: 'HTML'
        )
      end

      it 'validates message content before sending' do
        message = Telegram::AlertFormatter.format_signal_alert(signal)

        # Verify message contains required fields
        expect(message).to include('RELIANCE')
        expect(message).to include('LONG')
        expect(message).to include('2500')
        expect(message).to include('2400')
        expect(message).to include('2700')
        expect(message.length).to be < 4096
      end
    end

    context 'when sending exit alert' do
      let(:signal) do
        {
          symbol: 'RELIANCE',
          direction: :long
        }
      end

      it 'sends exit alert with P&L information' do
        allow(::TelegramNotifier).to receive(:enabled?).and_return(true)
        allow(::TelegramNotifier).to receive(:send_message).and_return(true)

        Telegram::Notifier.send_exit_alert(
          signal,
          exit_reason: 'take_profit',
          exit_price: 2700.0,
          pnl: 10000.0
        )

        expect(::TelegramNotifier).to have_received(:send_message).with(
          anything,
          parse_mode: 'HTML'
        )
      end
    end

    context 'when sending error alert' do
      it 'sends error notification' do
        allow(::TelegramNotifier).to receive(:enabled?).and_return(true)
        allow(::TelegramNotifier).to receive(:send_message).and_return(true)

        Telegram::Notifier.send_error_alert('Test error message', context: 'TestContext')

        expect(::TelegramNotifier).to have_received(:send_message).with(
          anything,
          parse_mode: 'HTML'
        )
      end
    end

    context 'when sending portfolio snapshot' do
      let(:portfolio_data) do
        {
          total_value: 110_000.0,
          total_pnl: 10_000.0,
          total_pnl_pct: 10.0,
          positions: [
            { symbol: 'RELIANCE', pnl: 5000.0, pnl_pct: 5.0 },
            { symbol: 'TCS', pnl: 5000.0, pnl_pct: 5.0 }
          ]
        }
      end

      it 'sends portfolio snapshot' do
        allow(::TelegramNotifier).to receive(:enabled?).and_return(true)
        allow(::TelegramNotifier).to receive(:send_message).and_return(true)

        Telegram::Notifier.send_portfolio_snapshot(portfolio_data)

        expect(::TelegramNotifier).to have_received(:send_message).with(
          anything,
          parse_mode: 'HTML'
        )
      end
    end

    context 'message rendering validation' do
      it 'ensures all message types render correctly' do
        # Test daily candidates
        candidates_msg = Telegram::AlertFormatter.format_daily_candidates([
          { symbol: 'TEST', score: 80.0, ai_score: 75.0, direction: 'long', instrument_id: 1, indicators: {} }
        ])
        expect(candidates_msg).to be_a(String)
        expect(candidates_msg.length).to be < 4096

        # Test signal alert
        signal_msg = Telegram::AlertFormatter.format_signal_alert(
          symbol: 'TEST',
          direction: :long,
          entry_price: 100.0,
          sl: 95.0,
          tp: 110.0,
          rr: 2.0,
          confidence: 80.0
        )
        expect(signal_msg).to be_a(String)
        expect(signal_msg.length).to be < 4096

        # Test exit alert
        exit_msg = Telegram::AlertFormatter.format_exit_alert(
          { symbol: 'TEST', direction: :long },
          exit_reason: 'take_profit',
          exit_price: 110.0,
          pnl: 1000.0
        )
        expect(exit_msg).to be_a(String)
        expect(exit_msg.length).to be < 4096

        # Test error alert
        error_msg = Telegram::AlertFormatter.format_error_alert('Test error', context: 'Test')
        expect(error_msg).to be_a(String)
        expect(error_msg.length).to be < 4096

        # Test portfolio snapshot
        portfolio_msg = Telegram::AlertFormatter.format_portfolio_snapshot(
          total_value: 100_000.0,
          total_pnl: 5000.0,
          total_pnl_pct: 5.0,
          positions: []
        )
        expect(portfolio_msg).to be_a(String)
        expect(portfolio_msg.length).to be < 4096
      end

      it 'handles empty data gracefully' do
        empty_candidates_msg = Telegram::AlertFormatter.format_daily_candidates([])
        expect(empty_candidates_msg).to be_a(String)
        expect(empty_candidates_msg.length).to be < 4096
        expect(empty_candidates_msg.downcase).to match(/no candidates|empty/)

        empty_portfolio_msg = Telegram::AlertFormatter.format_portfolio_snapshot(
          total_value: 100_000.0,
          total_pnl: 0.0,
          total_pnl_pct: 0.0,
          positions: []
        )
        expect(empty_portfolio_msg).to be_a(String)
        expect(empty_portfolio_msg.length).to be < 4096
      end

      it 'escapes HTML special characters' do
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

        # Should not contain raw script tags
        expect(message).not_to include('<script>')
        expect(message.length).to be < 4096
      end

      it 'handles large candidate lists by truncating' do
        # Create 100 candidates
        large_candidates = 100.times.map do |i|
          {
            symbol: "STOCK#{i}",
            score: 80.0 + i,
            ai_score: 75.0 + i,
            direction: 'long',
            instrument_id: i,
            indicators: { rsi: 65, ema20: 2500.0 }
          }
        end

        message = Telegram::AlertFormatter.format_daily_candidates(large_candidates)

        # Should be under Telegram's 4096 character limit
        expect(message.length).to be < 4096
        # Should still contain some candidates
        expect(message).to include('STOCK')
      end
    end

    context 'rate limiting and error handling' do
      it 'handles rate limit errors' do
        allow(::TelegramNotifier).to receive(:enabled?).and_return(true)
        allow(::TelegramNotifier).to receive(:send_message).and_raise(StandardError.new('Rate limit exceeded'))

        expect do
          Telegram::Notifier.send_signal_alert(
            symbol: 'TEST',
            direction: :long,
            entry_price: 100.0,
            sl: 95.0,
            tp: 110.0,
            rr: 2.0,
            confidence: 80.0
          )
        end.not_to raise_error
      end

      it 'handles network errors' do
        allow(::TelegramNotifier).to receive(:enabled?).and_return(true)
        allow(::TelegramNotifier).to receive(:send_message).and_raise(StandardError.new('Network error'))

        expect do
          Telegram::Notifier.send_signal_alert(
            symbol: 'TEST',
            direction: :long,
            entry_price: 100.0,
            sl: 95.0,
            tp: 110.0,
            rr: 2.0,
            confidence: 80.0
          )
        end.not_to raise_error
      end
    end
  end
end

