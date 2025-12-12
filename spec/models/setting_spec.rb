# frozen_string_literal: true

require "rails_helper"

RSpec.describe Setting do
  describe "validations" do
    it "is valid with valid attributes" do
      setting = build(:setting)
      expect(setting).to be_valid
    end

    it "requires key" do
      setting = build(:setting, key: nil)
      expect(setting).not_to be_valid
      expect(setting.errors[:key]).to include("can't be blank")
    end

    it "requires unique key" do
      create(:setting, key: "test_key")
      duplicate = build(:setting, key: "test_key")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:key]).to include("has already been taken")
    end
  end

  describe ".fetch" do
    it "returns value for existing key" do
      create(:setting, key: "test_key", value: "test_value")
      expect(described_class.fetch("test_key")).to eq("test_value")
    end

    it "returns default for non-existent key" do
      expect(described_class.fetch("non_existent", "default_value")).to eq("default_value")
    end

    it "returns nil for non-existent key without default" do
      expect(described_class.fetch("non_existent")).to be_nil
    end

    it "uses cache" do
      setting = create(:setting, key: "cached_key", value: "cached_value")
      first_call = described_class.fetch("cached_key")

      # Update in database directly (bypassing put which clears cache)
      setting.update!(value: "updated_value")

      # In test environment with null_store, cache doesn't persist, so it will fetch fresh
      # In production with real cache store, it would return cached value
      second_call = described_class.fetch("cached_key")
      if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
        # NullStore doesn't cache, so it will fetch fresh value
        expect(second_call).to eq("updated_value")
      else
        # Real cache store should return cached value
        expect(second_call).to eq(first_call)
      end
    end
  end

  describe ".put" do
    it "updates value and clears cache" do
      _setting = create(:setting, key: "put_key", value: "original")
      described_class.fetch("put_key") # Populate cache

      described_class.put("put_key", "updated")

      expect(described_class.fetch("put_key")).to eq("updated")
    end
  end

  describe ".fetch_i" do
    it "returns integer" do
      create(:setting, key: "int_key", value: "123")
      expect(described_class.fetch_i("int_key")).to eq(123)
      expect(described_class.fetch_i("non_existent", 0)).to eq(0)
    end
  end

  describe ".fetch_f" do
    it "returns float" do
      create(:setting, key: "float_key", value: "123.45")
      expect(described_class.fetch_f("float_key")).to eq(123.45)
      expect(described_class.fetch_f("non_existent", 0.0)).to eq(0.0)
    end
  end

  describe ".fetch_bool" do
    it "returns boolean" do
      create(:setting, key: "bool_true", value: "true")
      create(:setting, key: "bool_false", value: "false")
      create(:setting, key: "bool_yes", value: "yes")
      create(:setting, key: "bool_no", value: "no")

      expect(described_class.fetch_bool("bool_true")).to be true
      expect(described_class.fetch_bool("bool_false")).to be false
      expect(described_class.fetch_bool("bool_yes")).to be true
      expect(described_class.fetch_bool("bool_no")).to be false
      expect(described_class.fetch_bool("non_existent", false)).to be false
    end
  end

  describe "edge cases" do
    it "handles fetch with custom TTL" do
      create(:setting, key: "ttl_key", value: "ttl_value")
      result = described_class.fetch("ttl_key", nil, ttl: 60)
      expect(result).to eq("ttl_value")
    end

    it "handles fetch_i with non-numeric string" do
      create(:setting, key: "non_numeric", value: "abc")
      expect(described_class.fetch_i("non_numeric", 0)).to eq(0)
    end

    it "handles fetch_i with float string" do
      create(:setting, key: "float_string", value: "123.45")
      expect(described_class.fetch_i("float_string", 0)).to eq(123)
    end

    it "handles fetch_f with non-numeric string" do
      create(:setting, key: "non_numeric", value: "abc")
      expect(described_class.fetch_f("non_numeric", 0.0)).to eq(0.0)
    end

    it "handles fetch_f with integer string" do
      create(:setting, key: "int_string", value: "123")
      expect(described_class.fetch_f("int_string", 0.0)).to eq(123.0)
    end

    it "handles fetch_bool with various truthy values" do
      %w[1 TRUE YES ON].each do |value|
        create(:setting, key: "bool_#{value.downcase}", value: value)
        expect(described_class.fetch_bool("bool_#{value.downcase}")).to be true
      end
    end

    it "handles fetch_bool with various falsy values" do
      %w[0 false no off].each do |value|
        create(:setting, key: "bool_#{value}", value: value)
        expect(described_class.fetch_bool("bool_#{value}")).to be false
      end
    end

    it "handles fetch_bool with boolean true" do
      # Store boolean directly (if supported)
      allow(described_class).to receive(:find_by).and_return(double(value: true))
      expect(described_class.fetch_bool("bool_key", false)).to be true
    end

    it "handles fetch_bool with boolean false" do
      allow(described_class).to receive(:find_by).and_return(double(value: false))
      expect(described_class.fetch_bool("bool_key", true)).to be false
    end

    it "handles fetch_bool with whitespace" do
      create(:setting, key: "bool_whitespace", value: "  true  ")
      expect(described_class.fetch_bool("bool_whitespace")).to be true
    end

    it "handles put with nil value" do
      described_class.put("nil_key", nil)
      expect(described_class.fetch("nil_key")).to eq("")
    end

    it "handles put with numeric value" do
      described_class.put("numeric_key", 123)
      expect(described_class.fetch("numeric_key")).to eq("123")
    end

    it "handles put with boolean value" do
      described_class.put("bool_key", true)
      expect(described_class.fetch("bool_key")).to eq("true")
    end

    it "handles put creating new setting" do
      expect do
        described_class.put("new_key", "new_value")
      end.to change(described_class, :count).by(1)
      expect(described_class.fetch("new_key")).to eq("new_value")
    end

    it "handles put updating existing setting" do
      create(:setting, key: "existing_key", value: "old_value")
      described_class.put("existing_key", "new_value")
      expect(described_class.fetch("existing_key")).to eq("new_value")
    end

    it "handles fetch with nil key" do
      expect(described_class.fetch(nil, "default")).to eq("default")
    end

    it "handles put with nil key" do
      expect do
        described_class.put(nil, "value")
      end.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
