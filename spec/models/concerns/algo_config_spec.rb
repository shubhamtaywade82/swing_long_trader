# frozen_string_literal: true

require "rails_helper"

RSpec.describe AlgoConfig, type: :module do
  let(:config_path) { Rails.root.join("config/algo.yml") }
  let(:test_config) do
    {
      swing_trading: {
        enabled: true,
        strategy: {
          min_confidence: 0.7,
        },
      },
    }
  end

  before do
    allow(File).to receive(:read).with(config_path).and_return(test_config.to_yaml)
    described_class.reload!
  end

  describe ".fetch" do
    context "when key_path is nil" do
      it "returns entire config" do
        result = described_class.fetch

        expect(result).to be_a(Hash)
        expect(result[:swing_trading]).to be_present
      end
    end

    context "when key_path is a symbol" do
      it "fetches value by symbol key" do
        result = described_class.fetch(:swing_trading)

        expect(result).to be_a(Hash)
        expect(result[:enabled]).to be true
      end
    end

    context "when key_path is a string" do
      it "fetches value using dot notation" do
        result = described_class.fetch("swing_trading.enabled")

        expect(result).to be true
      end
    end

    context "when key_path is an array" do
      it "fetches nested value" do
        result = described_class.fetch(%i[swing_trading strategy min_confidence])

        expect(result).to eq(0.7)
      end
    end

    context "when key does not exist" do
      it "returns nil" do
        result = described_class.fetch(:nonexistent)

        expect(result).to be_nil
      end

      it "returns default when provided" do
        result = described_class.fetch(:nonexistent, "default_value")

        expect(result).to eq("default_value")
      end
    end
  end

  describe ".reload!" do
    it "reloads config from file" do
      described_class.reload!

      expect(described_class.fetch).to be_a(Hash)
    end
  end

  describe ".[]" do
    it "fetches value using bracket notation" do
      result = described_class[:swing_trading]

      expect(result).to be_a(Hash)
    end
  end

  describe ".load_config" do
    it "loads config from YAML file" do
      config = described_class.load_config

      expect(config).to be_a(Hash)
    end

    it "handles ERB in config file" do
      erb_content = <<~YAML
        swing_trading:
          enabled: <%= true %>
          test_value: <%= 100 %>
      YAML
      allow(File).to receive(:read).with(config_path).and_return(erb_content)
      described_class.reload!

      config = described_class.load_config

      expect(config[:swing_trading][:enabled]).to be true
      expect(config[:swing_trading][:test_value]).to eq(100)
    end

    it "handles empty config file" do
      allow(File).to receive(:read).with(config_path).and_return("")
      described_class.reload!

      config = described_class.load_config

      expect(config).to eq({})
    end

    it "handles nil config file" do
      allow(File).to receive(:read).with(config_path).and_return("null")
      described_class.reload!

      config = described_class.load_config

      expect(config).to eq({})
    end
  end

  describe "edge cases" do
    it "handles string keys in config" do
      allow(File).to receive(:read).with(config_path).and_return({ "swing_trading" => { "enabled" => true } }.to_yaml)
      described_class.reload!

      result = described_class.fetch("swing_trading.enabled")

      expect(result).to be true
    end

    it "handles symbol keys in config" do
      allow(File).to receive(:read).with(config_path).and_return({ swing_trading: { enabled: true } }.to_yaml)
      described_class.reload!

      result = described_class.fetch(:swing_trading)

      expect(result).to be_a(Hash)
    end

    it "handles nested non-hash values" do
      allow(File).to receive(:read).with(config_path).and_return({ swing_trading: "string_value" }.to_yaml)
      described_class.reload!

      result = described_class.fetch(%i[swing_trading enabled])

      expect(result).to be_nil
    end

    it "handles array with single element" do
      result = described_class.fetch([:swing_trading])

      expect(result).to be_a(Hash)
    end
  end
end
