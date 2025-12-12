# frozen_string_literal: true

require "database_cleaner/active_record"

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before do |example|
    # Use truncation strategy for rake task tests as they may commit transactions
    # outside of the test transaction scope
    DatabaseCleaner.strategy = if example.metadata[:type] == :task || example.full_description.include?("rake")
                                 :truncation
                               else
                                 :transaction
                               end
  end

  config.around do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  config.after do
    # Reset to transaction strategy after each example
    DatabaseCleaner.strategy = :transaction
  end
end
