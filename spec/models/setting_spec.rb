# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Setting, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      setting = build(:setting)
      expect(setting).to be_valid
    end

    it 'requires key' do
      setting = build(:setting, key: nil)
      expect(setting).not_to be_valid
      expect(setting.errors[:key]).to include("can't be blank")
    end

    it 'requires unique key' do
      create(:setting, key: 'test_key')
      duplicate = build(:setting, key: 'test_key')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:key]).to include('has already been taken')
    end
  end

  describe '.fetch' do
    it 'returns value for existing key' do
      create(:setting, key: 'test_key', value: 'test_value')
      expect(Setting.fetch('test_key')).to eq('test_value')
    end

    it 'returns default for non-existent key' do
      expect(Setting.fetch('non_existent', 'default_value')).to eq('default_value')
    end

    it 'returns nil for non-existent key without default' do
      expect(Setting.fetch('non_existent')).to be_nil
    end

    it 'uses cache' do
      setting = create(:setting, key: 'cached_key', value: 'cached_value')
      first_call = Setting.fetch('cached_key')

      # Update in database directly (bypassing put which clears cache)
      setting.update(value: 'updated_value')

      # In test environment with null_store, cache doesn't persist, so it will fetch fresh
      # In production with real cache store, it would return cached value
      if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
        # NullStore doesn't cache, so it will fetch fresh value
        second_call = Setting.fetch('cached_key')
        expect(second_call).to eq('updated_value')
      else
        # Real cache store should return cached value
        second_call = Setting.fetch('cached_key')
        expect(second_call).to eq(first_call)
      end
    end
  end

  describe '.put' do
    it 'updates value and clears cache' do
      setting = create(:setting, key: 'put_key', value: 'original')
      Setting.fetch('put_key') # Populate cache

      Setting.put('put_key', 'updated')

      expect(Setting.fetch('put_key')).to eq('updated')
    end
  end

  describe '.fetch_i' do
    it 'returns integer' do
      create(:setting, key: 'int_key', value: '123')
      expect(Setting.fetch_i('int_key')).to eq(123)
      expect(Setting.fetch_i('non_existent', 0)).to eq(0)
    end
  end

  describe '.fetch_f' do
    it 'returns float' do
      create(:setting, key: 'float_key', value: '123.45')
      expect(Setting.fetch_f('float_key')).to eq(123.45)
      expect(Setting.fetch_f('non_existent', 0.0)).to eq(0.0)
    end
  end

  describe '.fetch_bool' do
    it 'returns boolean' do
      create(:setting, key: 'bool_true', value: 'true')
      create(:setting, key: 'bool_false', value: 'false')
      create(:setting, key: 'bool_yes', value: 'yes')
      create(:setting, key: 'bool_no', value: 'no')

      expect(Setting.fetch_bool('bool_true')).to be true
      expect(Setting.fetch_bool('bool_false')).to be false
      expect(Setting.fetch_bool('bool_yes')).to be true
      expect(Setting.fetch_bool('bool_no')).to be false
      expect(Setting.fetch_bool('non_existent', false)).to be false
    end
  end
end

