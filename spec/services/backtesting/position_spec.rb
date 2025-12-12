# frozen_string_literal: true

require "rails_helper"

RSpec.describe Backtesting::Position, type: :service do
  let(:position) do
    described_class.new(
      instrument_id: 1,
      entry_date: Time.zone.today,
      entry_price: 100.0,
      quantity: 10,
      direction: :long,
      stop_loss: 95.0,
      take_profit: 110.0,
    )
  end

  describe "#initialize" do
    it "initializes position with correct attributes" do
      expect(position.instrument_id).to eq(1)
      expect(position.entry_price).to eq(100.0)
      expect(position.quantity).to eq(10)
      expect(position.direction).to eq(:long)
      expect(position.stop_loss).to eq(95.0)
      expect(position.take_profit).to eq(110.0)
    end
  end

  describe "#close" do
    it "closes position with exit details" do
      position.close(
        exit_date: Time.zone.today + 1,
        exit_price: 110.0,
        exit_reason: "tp_hit",
      )

      expect(position.closed?).to be true
      expect(position.exit_date).to eq(Time.zone.today + 1)
      expect(position.exit_price).to eq(110.0)
      expect(position.exit_reason).to eq("tp_hit")
    end
  end

  describe "#closed?" do
    context "when position is open" do
      it "returns false" do
        expect(position.closed?).to be false
      end
    end

    context "when position is closed" do
      before do
        position.close(exit_date: Time.zone.today, exit_price: 110.0, exit_reason: "tp_hit")
      end

      it "returns true" do
        expect(position.closed?).to be true
      end
    end
  end

  describe "#calculate_pnl" do
    context "for long position" do
      it "calculates profit correctly" do
        pnl = position.calculate_pnl(110.0)

        expect(pnl).to eq(100.0) # (110 - 100) * 10
      end

      it "calculates loss correctly" do
        pnl = position.calculate_pnl(95.0)

        expect(pnl).to eq(-50.0) # (95 - 100) * 10
      end
    end

    context "for short position" do
      let(:short_position) do
        described_class.new(
          instrument_id: 1,
          entry_date: Time.zone.today,
          entry_price: 100.0,
          quantity: 10,
          direction: :short,
          stop_loss: 105.0,
          take_profit: 90.0,
        )
      end

      it "calculates profit correctly" do
        pnl = short_position.calculate_pnl(90.0)

        expect(pnl).to eq(100.0) # (100 - 90) * 10
      end

      it "calculates loss correctly" do
        pnl = short_position.calculate_pnl(105.0)

        expect(pnl).to eq(-50.0) # (100 - 105) * 10
      end
    end
  end

  describe "#check_exit" do
    context "for long position" do
      it "returns exit info when stop loss is hit" do
        result = position.check_exit(94.0, Time.zone.today)

        expect(result).to be_present
        expect(result[:exit_reason]).to eq("stop_loss")
        expect(result[:exit_price]).to eq(95.0)
      end

      it "returns exit info when take profit is hit" do
        result = position.check_exit(110.0, Time.zone.today)

        expect(result).to be_present
        expect(result[:exit_reason]).to eq("take_profit")
        expect(result[:exit_price]).to eq(110.0)
      end

      it "returns nil when no exit condition is met" do
        result = position.check_exit(102.0, Time.zone.today)

        expect(result).to be_nil
      end
    end

    context "for short position" do
      let(:short_position) do
        described_class.new(
          instrument_id: 1,
          entry_date: Time.zone.today,
          entry_price: 100.0,
          quantity: 10,
          direction: :short,
          stop_loss: 105.0,
          take_profit: 90.0,
        )
      end

      it "returns exit info when stop loss is hit" do
        result = short_position.check_exit(106.0, Time.zone.today)

        expect(result).to be_present
        expect(result[:exit_reason]).to eq("stop_loss")
        expect(result[:exit_price]).to eq(105.0)
      end

      it "returns exit info when take profit is hit" do
        result = short_position.check_exit(90.0, Time.zone.today)

        expect(result).to be_present
        expect(result[:exit_reason]).to eq("take_profit")
        expect(result[:exit_price]).to eq(90.0)
      end

      it "returns nil when no exit condition is met" do
        result = short_position.check_exit(98.0, Time.zone.today)

        expect(result).to be_nil
      end
    end

    context "when position is already closed" do
      before do
        position.close(exit_date: Time.zone.today, exit_price: 110.0, exit_reason: "tp_hit")
      end

      it "returns nil" do
        result = position.check_exit(120.0, Time.zone.today)

        expect(result).to be_nil
      end
    end
  end
end
