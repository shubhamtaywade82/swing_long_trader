# frozen_string_literal: true

require "rails_helper"

RSpec.describe Strategies::Swing::ExitMonitorJob, type: :job do
  let(:instrument) { create(:instrument, symbol_name: "RELIANCE", ltp: 2550.0) }
  let(:position) do
    create(:position,
           instrument: instrument,
           symbol: "RELIANCE",
           direction: "long",
           entry_price: 2500.0,
           current_price: 2550.0,
           quantity: 10,
           stop_loss: 2450.0,
           take_profit: 2600.0,
           tp1: 2550.0, # Entry + (ATR × 2)
           tp2: 2600.0, # Entry + (ATR × 4)
           atr: 25.0,
           atr_trailing_multiplier: 1.5,
           initial_stop_loss: 2450.0,
           tp1_hit: false,
           status: "open",
           opened_at: 1.day.ago)
  end

  describe "#check_exit_conditions_for_position" do
    context "when TP1 is hit" do
      it "moves stop to breakeven and continues to TP2" do
        position.update!(current_price: 2550.0) # TP1 price

        allow(Position).to receive(:open).and_return([position])
        allow(position.instrument).to receive(:ltp).and_return(2550.0)

        # Mock the exit check
        job = described_class.new
        exit_check = job.send(:check_exit_conditions_for_position, position)

        # Should not exit yet (waiting for TP2)
        expect(exit_check[:should_exit]).to be false

        # TP1 should be marked as hit
        position.reload
        expect(position.tp1_hit).to be true
        expect(position.stop_loss).to eq(2500.0) # Breakeven
        expect(position.breakeven_stop).to eq(2500.0)
      end
    end

    context "when TP2 is hit" do
      it "triggers exit" do
        position.update!(current_price: 2600.0, tp1_hit: true) # TP2 price

        allow(Position).to receive(:open).and_return([position])
        allow(position.instrument).to receive(:ltp).and_return(2600.0)

        job = described_class.new
        exit_check = job.send(:check_exit_conditions_for_position, position)

        expect(exit_check[:should_exit]).to be true
        expect(exit_check[:reason]).to eq("tp2_hit")
        expect(exit_check[:exit_price]).to eq(2600.0)
      end
    end

    context "when ATR trailing stop is triggered" do
      it "exits position" do
        # Price moved up to 2550, then fell to trailing stop level
        position.update!(
          current_price: 2510.0,
          highest_price: 2550.0,
          stop_loss: 2512.5, # Trailing stop: 2550 - (25 × 1.5) = 2512.5
        )

        allow(Position).to receive(:open).and_return([position])
        allow(position.instrument).to receive(:ltp).and_return(2510.0)

        job = described_class.new
        exit_check = job.send(:check_exit_conditions_for_position, position)

        expect(exit_check[:should_exit]).to be true
        expect(exit_check[:reason]).to eq("trailing_stop")
      end
    end
  end
end
