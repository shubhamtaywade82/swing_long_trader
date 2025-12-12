# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telegram::AlertFormatter, type: :service do
  describe ".format_daily_candidates" do
    it "formats daily candidates" do
      candidates = [
        { symbol: "RELIANCE", score: 85.0, ai_score: 80.0 },
        { symbol: "TCS", score: 82.0, ai_score: 75.0 },
      ]

      message = described_class.format_daily_candidates(candidates)

      expect(message).not_to be_nil
      expect(message).to include("RELIANCE")
      expect(message).to include("TCS")
    end

    it "handles empty candidates list" do
      message = described_class.format_daily_candidates([])

      expect(message).not_to be_nil
      expect(message.downcase).to match(/no candidates|empty/)
    end
  end

  describe ".format_signal_alert" do
    it "formats signal alert" do
      signal = {
        symbol: "RELIANCE",
        direction: :long,
        entry_price: 2500.0,
        sl: 2400.0,
        tp: 2700.0,
        rr: 2.0,
        confidence: 85.0,
      }

      message = described_class.format_signal_alert(signal)

      expect(message).not_to be_nil
      expect(message).to include("RELIANCE")
      expect(message).to include("LONG")
      expect(message).to include("2500")
    end

    it "escapes HTML in messages" do
      signal = {
        symbol: '<script>alert("xss")</script>',
        direction: :long,
        entry_price: 100.0,
        sl: 95.0,
        tp: 110.0,
        rr: 2.0,
        confidence: 80.0,
      }

      message = described_class.format_signal_alert(signal)

      # Should not contain raw script tags
      expect(message).not_to include("<script>")
    end
  end

  describe ".format_exit_alert" do
    it "formats exit alert" do
      signal = {
        symbol: "RELIANCE",
        direction: :long,
      }

      message = described_class.format_exit_alert(
        signal,
        exit_reason: "take_profit",
        exit_price: 2700.0,
        pnl: 10_000.0,
      )

      expect(message).not_to be_nil
      expect(message).to include("RELIANCE")
      expect(message).to include("take_profit")
      expect(message).to include("10000")
    end
  end

  describe ".format_error_alert" do
    it "formats error alert" do
      message = described_class.format_error_alert(
        "Test error message",
        context: "TestContext",
      )

      expect(message).not_to be_nil
      expect(message).to include("Error Alert")
      expect(message).to include("Test error message")
      expect(message).to include("TestContext")
    end
  end

  describe ".format_portfolio_snapshot" do
    it "formats portfolio snapshot" do
      portfolio_data = {
        total_value: 110_000.0,
        total_pnl: 10_000.0,
        total_pnl_pct: 10.0,
        open_positions: 2,
        closed_positions: 5,
        win_rate: 60.0,
        positions: [
          { symbol: "RELIANCE", pnl: 5000.0, pnl_pct: 5.0 },
        ],
      }

      message = described_class.format_portfolio_snapshot(portfolio_data)

      expect(message).not_to be_nil
      expect(message).to include("10000") # total_pnl
      expect(message).to include("RELIANCE")
      expect(message).to include("2") # open_positions
      expect(message).to include("5") # closed_positions
      expect(message).to include("60.0") # win_rate
    end

    it "handles negative P&L" do
      portfolio_data = {
        total_pnl: -5000.0,
        total_pnl_pct: -5.0,
        open_positions: 1,
        closed_positions: 2,
        win_rate: 30.0,
      }

      message = described_class.format_portfolio_snapshot(portfolio_data)
      expect(message).to include("-5000")
      expect(message).to include("-5.0")
    end

    it "handles zero P&L" do
      portfolio_data = {
        total_pnl: 0,
        total_pnl_pct: 0,
        open_positions: 0,
        closed_positions: 0,
        win_rate: 0,
      }

      message = described_class.format_portfolio_snapshot(portfolio_data)
      expect(message).to include("0")
    end

    it "limits positions to 5" do
      portfolio_data = {
        total_pnl: 1000.0,
        positions: (1..10).map { |i| { symbol: "STOCK#{i}", pnl: 100.0 } },
      }

      message = described_class.format_portfolio_snapshot(portfolio_data)
      expect(message.scan("STOCK").count).to eq(5)
    end

    it "handles missing positions array" do
      portfolio_data = {
        total_pnl: 1000.0,
        open_positions: 2,
      }

      message = described_class.format_portfolio_snapshot(portfolio_data)
      expect(message).to include("1000")
      expect(message).not_to include("Open Positions:")
    end
  end

  describe ".format_daily_candidates" do
    it "handles more than 10 candidates" do
      candidates = (1..15).map { |i| { symbol: "STOCK#{i}", score: 80.0 } }
      message = described_class.format_daily_candidates(candidates)
      expect(message.scan("STOCK").count).to eq(10)
    end

    it "handles candidates with instrument_id instead of symbol" do
      candidates = [{ instrument_id: "12345", score: 85.0 }]
      message = described_class.format_daily_candidates(candidates)
      expect(message).to include("12345")
    end

    it "handles candidates with metadata and indicators" do
      candidates = [{
        symbol: "RELIANCE",
        score: 85.0,
        metadata: { trend_alignment: %w[EMA20 EMA50] },
      }]
      message = described_class.format_daily_candidates(candidates)
      expect(message).to include("EMA20")
      expect(message).to include("EMA50")
    end

    it "handles short direction candidates" do
      candidates = [{ symbol: "STOCK", score: 85.0, direction: "short" }]
      message = described_class.format_daily_candidates(candidates)
      expect(message).to include("🔴")
    end
  end

  describe ".format_signal_alert" do
    it "handles short direction" do
      signal = {
        symbol: "RELIANCE",
        direction: :short,
        entry_price: 2500.0,
        sl: 2600.0,
        tp: 2300.0,
        rr: 2.0,
        confidence: 85.0,
      }

      message = described_class.format_signal_alert(signal)
      expect(message).to include("SHORT")
      expect(message).to include("🔴")
    end

    it "handles missing optional fields" do
      signal = {
        symbol: "RELIANCE",
        direction: :long,
      }

      message = described_class.format_signal_alert(signal)
      expect(message).to include("RELIANCE")
      expect(message).to include("0") # Default values
    end

    it "handles metadata with ATR percentage" do
      signal = {
        symbol: "RELIANCE",
        direction: :long,
        entry_price: 2500.0,
        metadata: { atr_pct: 2.5 },
      }

      message = described_class.format_signal_alert(signal)
      expect(message).to include("ATR %")
      expect(message).to include("2.5")
    end
  end

  describe ".format_exit_alert" do
    it "handles positive P&L" do
      signal = { symbol: "RELIANCE", entry_price: 100.0, qty: 10 }
      message = described_class.format_exit_alert(
        signal,
        exit_reason: "tp_hit",
        exit_price: 110.0,
        pnl: 100.0,
      )
      expect(message).to include("✅")
      expect(message).to include("+")
    end

    it "handles negative P&L" do
      signal = { symbol: "RELIANCE", entry_price: 100.0, qty: 10 }
      message = described_class.format_exit_alert(
        signal,
        exit_reason: "sl_hit",
        exit_price: 90.0,
        pnl: -100.0,
      )
      expect(message).to include("❌")
      expect(message).to include("-")
    end

    it "handles zero P&L" do
      signal = { symbol: "RELIANCE", entry_price: 100.0, qty: 10 }
      message = described_class.format_exit_alert(
        signal,
        exit_reason: "time_based",
        exit_price: 100.0,
        pnl: 0,
      )
      expect(message).to include("⚪")
    end

    it "handles zero entry_price for P&L percentage" do
      signal = { symbol: "RELIANCE", entry_price: 0, qty: 10 }
      message = described_class.format_exit_alert(
        signal,
        exit_reason: "tp_hit",
        exit_price: 110.0,
        pnl: 100.0,
      )
      expect(message).to include("100.0") # P&L value
      expect(message).not_to include("%") # No percentage if entry_price is 0
    end
  end

  describe ".format_error_alert" do
    it "handles error without context" do
      message = described_class.format_error_alert("Test error")
      expect(message).to include("Error Alert")
      expect(message).to include("Test error")
      expect(message).not_to include("Context:")
    end
  end

  describe "#escape_html" do
    it "escapes HTML special characters" do
      formatter = described_class.new
      expect(formatter.send(:escape_html, "&")).to eq("&amp;")
      expect(formatter.send(:escape_html, "<")).to eq("&lt;")
      expect(formatter.send(:escape_html, ">")).to eq("&gt;")
      expect(formatter.send(:escape_html, '"')).to eq("&quot;")
      expect(formatter.send(:escape_html, "'")).to eq("&#39;")
    end

    it "handles nil input" do
      formatter = described_class.new
      expect(formatter.send(:escape_html, nil)).to be_nil
    end

    it "handles complex HTML strings" do
      formatter = described_class.new
      result = formatter.send(:escape_html, '<script>alert("xss")</script>')
      expect(result).not_to include("<script>")
      expect(result).not_to include('"')
    end
  end
end
