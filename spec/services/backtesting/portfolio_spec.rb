# frozen_string_literal: true

require "rails_helper"

RSpec.describe Backtesting::Portfolio, type: :service do
  let(:initial_capital) { 100_000.0 }
  let(:config) { Backtesting::Config.new(initial_capital: initial_capital) }
  let(:portfolio) { described_class.new(initial_capital: initial_capital, config: config) }
  let(:instrument_id) { 1 }

  describe "#initialize" do
    it "initializes with initial capital" do
      expect(portfolio.initial_capital).to eq(initial_capital)
      expect(portfolio.current_capital).to eq(initial_capital)
      expect(portfolio.positions).to be_empty
      expect(portfolio.closed_positions).to be_empty
    end
  end

  describe "#open_position" do
    context "when sufficient capital" do
      it "opens position and deducts capital" do
        result = portfolio.open_position(
          instrument_id: instrument_id,
          entry_date: Time.zone.today,
          entry_price: 100.0,
          quantity: 10,
          direction: :long,
          stop_loss: 95.0,
          take_profit: 110.0,
        )

        expect(result).to be true
        expect(portfolio.positions[instrument_id]).to be_present
        expect(portfolio.current_capital).to be < initial_capital
      end
    end

    context "when insufficient capital" do
      it "returns false" do
        result = portfolio.open_position(
          instrument_id: instrument_id,
          entry_date: Time.zone.today,
          entry_price: 100.0,
          quantity: 10_000, # Too large
          direction: :long,
          stop_loss: 95.0,
          take_profit: 110.0,
        )

        expect(result).to be false
        expect(portfolio.positions).to be_empty
      end
    end

    context "when position already exists" do
      before do
        portfolio.open_position(
          instrument_id: instrument_id,
          entry_date: Time.zone.today,
          entry_price: 100.0,
          quantity: 10,
          direction: :long,
          stop_loss: 95.0,
          take_profit: 110.0,
        )
      end

      it "replaces existing position" do
        portfolio.open_position(
          instrument_id: instrument_id,
          entry_date: Time.zone.today,
          entry_price: 105.0,
          quantity: 5,
          direction: :long,
          stop_loss: 100.0,
          take_profit: 115.0,
        )

        new_position = portfolio.positions[instrument_id]
        expect(new_position.entry_price).to eq(105.0)
        expect(new_position.quantity).to eq(5)
      end
    end
  end

  describe "#close_position" do
    before do
      portfolio.open_position(
        instrument_id: instrument_id,
        entry_date: Time.zone.today,
        entry_price: 100.0,
        quantity: 10,
        direction: :long,
        stop_loss: 95.0,
        take_profit: 110.0,
      )
    end

    context "when position exists" do
      it "closes position and adds proceeds to capital" do
        old_capital = portfolio.current_capital

        portfolio.close_position(
          instrument_id: instrument_id,
          exit_date: Time.zone.today + 1,
          exit_price: 110.0,
          exit_reason: "tp_hit",
        )

        expect(portfolio.positions[instrument_id]).to be_nil
        expect(portfolio.closed_positions.size).to eq(1)
        expect(portfolio.current_capital).to be > old_capital
      end
    end

    context "when position does not exist" do
      it "returns false" do
        result = portfolio.close_position(
          instrument_id: 999,
          exit_date: Time.zone.today,
          exit_price: 110.0,
          exit_reason: "tp_hit",
        )

        expect(result).to be false
      end
    end
  end

  describe "#update_equity" do
    before do
      portfolio.open_position(
        instrument_id: instrument_id,
        entry_date: Time.zone.today,
        entry_price: 100.0,
        quantity: 10,
        direction: :long,
        stop_loss: 95.0,
        take_profit: 110.0,
      )
    end

    it "updates equity curve" do
      prices = { instrument_id => 105.0 }
      portfolio.update_equity(Time.zone.today, prices)

      expect(portfolio.equity_curve.last[:equity]).to be > initial_capital
    end
  end

  describe "#total_equity" do
    before do
      portfolio.open_position(
        instrument_id: instrument_id,
        entry_date: Time.zone.today,
        entry_price: 100.0,
        quantity: 10,
        direction: :long,
        stop_loss: 95.0,
        take_profit: 110.0,
      )
    end

    it "calculates total equity including open positions" do
      prices = { instrument_id => 105.0 }
      equity = portfolio.total_equity(prices)

      expect(equity).to be > initial_capital
    end
  end
end
