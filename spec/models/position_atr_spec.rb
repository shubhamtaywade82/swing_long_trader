# frozen_string_literal: true

require "rails_helper"

RSpec.describe Position, type: :model do
  let(:instrument) { create(:instrument, symbol_name: "RELIANCE", ltp: 2500.0) }
  let(:position) do
    create(:position,
           instrument: instrument,
           symbol: "RELIANCE",
           direction: "long",
           entry_price: 2500.0,
           current_price: 2500.0,
           quantity: 10,
           stop_loss: 2450.0,
           take_profit: 2600.0,
           tp1: 2550.0, # Entry + (ATR × 2) = 2500 + (25 × 2) = 2550
           tp2: 2600.0, # Entry + (ATR × 4) = 2500 + (25 × 4) = 2600
           atr: 25.0,
           atr_pct: 1.0,
           atr_trailing_multiplier: 1.5,
           initial_stop_loss: 2450.0,
           status: "open",
           opened_at: 1.day.ago)
  end

  describe "#check_tp1_hit?" do
    context "when TP1 is not hit" do
      it "returns false when price is below TP1" do
        position.update!(current_price: 2540.0)
        expect(position.check_tp1_hit?).to be false
      end

      it "returns false when TP1 is already hit" do
        position.update!(tp1_hit: true, current_price: 2560.0)
        expect(position.check_tp1_hit?).to be false
      end
    end

    context "when TP1 is hit" do
      it "returns true when price reaches TP1" do
        position.update!(current_price: 2550.0)
        expect(position.check_tp1_hit?).to be true
      end

      it "returns true when price exceeds TP1" do
        position.update!(current_price: 2560.0)
        expect(position.check_tp1_hit?).to be true
      end
    end
  end

  describe "#check_tp2_hit?" do
    context "when TP2 is not hit" do
      it "returns false when price is below TP2" do
        position.update!(current_price: 2580.0)
        expect(position.check_tp2_hit?).to be false
      end
    end

    context "when TP2 is hit" do
      it "returns true when price reaches TP2" do
        position.update!(current_price: 2600.0)
        expect(position.check_tp2_hit?).to be true
      end

      it "returns true when price exceeds TP2" do
        position.update!(current_price: 2620.0)
        expect(position.check_tp2_hit?).to be true
      end
    end
  end

  describe "#move_stop_to_breakeven!" do
    it "moves stop loss to entry price" do
      position.update!(stop_loss: 2450.0, entry_price: 2500.0)

      result = position.move_stop_to_breakeven!

      expect(result).to be true
      expect(position.stop_loss).to eq(2500.0) # Entry price
      expect(position.breakeven_stop).to eq(2500.0)
      expect(position.initial_stop_loss).to eq(2450.0) # Original stop loss preserved
    end

    it "logs the breakeven stop movement" do
      expect(Rails.logger).to receive(:info).with(
        include("Moved stop to breakeven"),
      )

      position.move_stop_to_breakeven!
    end
  end

  describe "#check_atr_trailing_stop?" do
    context "when ATR trailing stop is configured" do
      it "updates stop loss when price moves higher" do
        position.update!(
          current_price: 2550.0,
          highest_price: 2550.0,
          stop_loss: 2450.0,
        )

        # Trailing stop should be: 2550 - (25 × 1.5) = 2512.5
        expect(position.check_atr_trailing_stop?).to be false
        position.reload
        expect(position.stop_loss).to be >= 2512.0 # Stop should be updated
      end

      it "triggers exit when price falls below trailing stop" do
        position.update!(
          current_price: 2510.0,
          highest_price: 2550.0,
          stop_loss: 2512.5, # Trailing stop at 2550 - (25 × 1.5) = 2512.5
        )

        expect(position.check_atr_trailing_stop?).to be true
      end
    end

    context "when ATR trailing stop is not configured" do
      it "returns false" do
        position.update!(atr_trailing_multiplier: nil, atr: nil)
        expect(position.check_atr_trailing_stop?).to be false
      end
    end
  end

  describe "#check_trailing_stop?" do
    context "when ATR trailing stop is configured" do
      it "uses ATR-based trailing stop" do
        position.update!(
          current_price: 2550.0,
          highest_price: 2550.0,
          stop_loss: 2450.0,
        )

        # Should check ATR trailing stop first
        expect(position).to receive(:check_atr_trailing_stop?).and_call_original
        position.check_trailing_stop?
      end
    end

    context "when only percentage trailing stop is configured" do
      it "falls back to percentage-based trailing stop" do
        position.update!(
          atr_trailing_multiplier: nil,
          trailing_stop_pct: 5.0,
          current_price: 2550.0,
          highest_price: 2550.0,
        )

        # Percentage trailing stop: 2550 × (1 - 0.05) = 2422.5
        expect(position.check_trailing_stop?).to be false # Price hasn't fallen below trailing stop
      end
    end
  end
end
