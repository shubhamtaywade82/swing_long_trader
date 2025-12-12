# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstrumentTypeMapping do
  describe ".underlying_for" do
    it "returns parent for child code" do
      expect(described_class.underlying_for("FUTIDX")).to eq("INDEX")
      expect(described_class.underlying_for("OPTSTK")).to eq("EQUITY")
    end

    it "returns the code itself if not a child" do
      expect(described_class.underlying_for("EQUITY")).to eq("EQUITY")
      expect(described_class.underlying_for("INDEX")).to eq("INDEX")
    end

    it "returns nil for blank code" do
      expect(described_class.underlying_for("")).to be_nil
      expect(described_class.underlying_for(nil)).to be_nil
    end
  end

  describe ".derivative_codes_for" do
    it "returns derivative codes for parent" do
      expect(described_class.derivative_codes_for("INDEX")).to eq(%w[FUTIDX OPTIDX])
      expect(described_class.derivative_codes_for("EQUITY")).to eq(%w[FUTSTK OPTSTK])
    end

    it "returns empty array for non-parent code" do
      expect(described_class.derivative_codes_for("INVALID")).to eq([])
    end
  end

  describe ".all_parents" do
    it "returns all parent codes" do
      parents = described_class.all_parents
      expect(parents).to include("INDEX", "EQUITY", "FUTCOM", "FUTCUR")
    end
  end

  describe ".all_children" do
    it "returns all child codes" do
      children = described_class.all_children
      expect(children).to include("FUTIDX", "OPTIDX", "FUTSTK", "OPTSTK", "OPTFUT", "OPTCUR")
    end
  end
end
