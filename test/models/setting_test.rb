# frozen_string_literal: true

require 'test_helper'

class SettingTest < ActiveSupport::TestCase
  test 'should be valid with valid attributes' do
    setting = build(:setting)
    assert setting.valid?
  end

  test 'should require key' do
    setting = build(:setting, key: nil)
    assert_not setting.valid?
    assert_includes setting.errors[:key], "can't be blank"
  end

  test 'should have unique key' do
    create(:setting, key: 'test_key')
    duplicate = build(:setting, key: 'test_key')
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key], 'has already been taken'
  end

  test 'fetch should return value for existing key' do
    create(:setting, key: 'test_key', value: 'test_value')
    assert_equal 'test_value', Setting.fetch('test_key')
  end

  test 'fetch should return default for non-existent key' do
    assert_equal 'default_value', Setting.fetch('non_existent', 'default_value')
  end

  test 'fetch should return nil for non-existent key without default' do
    assert_nil Setting.fetch('non_existent')
  end

  test 'fetch should use cache' do
    setting = create(:setting, key: 'cached_key', value: 'cached_value')
    first_call = Setting.fetch('cached_key')

    # Update in database
    setting.update(value: 'updated_value')

    # Should still return cached value
    second_call = Setting.fetch('cached_key')
    assert_equal first_call, second_call
  end

  test 'put should update value and clear cache' do
    setting = create(:setting, key: 'put_key', value: 'original')
    Setting.fetch('put_key') # Populate cache

    Setting.put('put_key', 'updated')

    assert_equal 'updated', Setting.fetch('put_key')
  end

  test 'fetch_i should return integer' do
    create(:setting, key: 'int_key', value: '123')
    assert_equal 123, Setting.fetch_i('int_key')
    assert_equal 0, Setting.fetch_i('non_existent', 0)
  end

  test 'fetch_f should return float' do
    create(:setting, key: 'float_key', value: '123.45')
    assert_equal 123.45, Setting.fetch_f('float_key')
    assert_equal 0.0, Setting.fetch_f('non_existent', 0.0)
  end

  test 'fetch_bool should return boolean' do
    create(:setting, key: 'bool_true', value: 'true')
    create(:setting, key: 'bool_false', value: 'false')
    create(:setting, key: 'bool_yes', value: 'yes')
    create(:setting, key: 'bool_no', value: 'no')

    assert_equal true, Setting.fetch_bool('bool_true')
    assert_equal false, Setting.fetch_bool('bool_false')
    assert_equal true, Setting.fetch_bool('bool_yes')
    assert_equal false, Setting.fetch_bool('bool_no')
    assert_equal false, Setting.fetch_bool('non_existent', false)
  end
end

