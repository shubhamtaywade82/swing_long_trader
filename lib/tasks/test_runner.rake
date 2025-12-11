# frozen_string_literal: true

namespace :test do
  desc 'Run all tests and code quality checks'
  task all: :environment do
    puts "\n=== 🧪 COMPLETE TEST SUITE ===\n\n"
    puts "Running all tests and code quality checks...\n\n"

    results = {}

    # 1. RSpec Tests
    puts "1️⃣  Running RSpec Tests..."
    puts "-" * 50
    if system('bundle exec rspec --format documentation')
      results[:rspec] = { status: :passed, message: 'All RSpec tests passed' }
      puts "\n✅ RSpec tests passed\n\n"
    else
      results[:rspec] = { status: :failed, message: 'RSpec tests failed' }
      puts "\n❌ RSpec tests failed\n\n"
    end

    # 2. RuboCop
    puts "2️⃣  Running RuboCop..."
    puts "-" * 50
    if system('bundle exec rubocop')
      results[:rubocop] = { status: :passed, message: 'No RuboCop violations' }
      puts "\n✅ RuboCop check passed\n\n"
    else
      results[:rubocop] = { status: :failed, message: 'RuboCop violations found' }
      puts "\n❌ RuboCop violations found\n\n"
    end

    # 3. Brakeman
    puts "3️⃣  Running Brakeman Security Check..."
    puts "-" * 50
    if system('bundle exec brakeman --no-pager')
      results[:brakeman] = { status: :passed, message: 'No security issues found' }
      puts "\n✅ Brakeman check passed\n\n"
    else
      results[:brakeman] = { status: :failed, message: 'Security issues found' }
      puts "\n❌ Security issues found\n\n"
    end

    # 4. Code Coverage
    puts "4️⃣  Checking Code Coverage..."
    puts "-" * 50
    if File.exist?(Rails.root.join('coverage/.last_run.json'))
      require 'json'
      coverage_data = JSON.parse(File.read(Rails.root.join('coverage/.last_run.json')))
      coverage = coverage_data['result']['covered_percent']
      threshold = 80.0

      if coverage >= threshold
        results[:coverage] = { status: :passed, message: "Code coverage: #{coverage.round(2)}% (threshold: #{threshold}%)" }
        puts "✅ Code coverage: #{coverage.round(2)}% (meets threshold of #{threshold}%)\n\n"
      else
        results[:coverage] = { status: :failed, message: "Code coverage: #{coverage.round(2)}% (below threshold of #{threshold}%)" }
        puts "❌ Code coverage: #{coverage.round(2)}% (below threshold of #{threshold}%)\n\n"
      end
    else
      results[:coverage] = { status: :warning, message: 'Code coverage not available - run RSpec tests first' }
      puts "⚠️  Code coverage not available - run RSpec tests first\n\n"
    end

    # Summary
    puts "\n=== 📊 TEST SUMMARY ===\n"
    results.each do |check, result|
      status_icon = case result[:status]
                    when :passed then '✅'
                    when :failed then '❌'
                    when :warning then '⚠️'
                    else '❓'
                    end
      puts "#{status_icon} #{check.to_s.upcase}: #{result[:message]}"
    end

    all_passed = results.values.all? { |r| r[:status] == :passed }
    puts "\n"

    if all_passed
      puts "✅ All tests and checks passed!\n"
    else
      puts "⚠️  Some tests or checks failed - review above\n"
    end

    puts "\n"
  end

  desc 'Run RSpec tests only'
  task rspec: :environment do
    puts "\n=== 🧪 RSPEC TESTS ===\n\n"
    system('bundle exec rspec --format documentation')
  end

  desc 'Run RuboCop only'
  task rubocop: :environment do
    puts "\n=== 🔍 RUBOCOP ===\n\n"
    system('bundle exec rubocop')
  end

  desc 'Run Brakeman only'
  task brakeman: :environment do
    puts "\n=== 🔒 BRAKEMAN ===\n\n"
    system('bundle exec brakeman --no-pager')
  end

  desc 'Check code coverage'
  task coverage: :environment do
    puts "\n=== 📊 CODE COVERAGE ===\n\n"
    if File.exist?(Rails.root.join('coverage/.last_run.json'))
      require 'json'
      coverage_data = JSON.parse(File.read(Rails.root.join('coverage/.last_run.json')))
      coverage = coverage_data['result']['covered_percent']
      threshold = 80.0

      puts "Coverage: #{coverage.round(2)}%"
      puts "Threshold: #{threshold}%"
      puts "\n"

      if coverage >= threshold
        puts "✅ Code coverage meets threshold"
      else
        puts "❌ Code coverage below threshold"
        puts "   Need: #{threshold}%"
        puts "   Have: #{coverage.round(2)}%"
        puts "   Missing: #{(threshold - coverage).round(2)}%"
      end
    else
      puts "⚠️  Code coverage not available"
      puts "   Run 'bundle exec rspec' first to generate coverage report"
    end
    puts "\n"
  end

  desc 'Verify test infrastructure (VCR, WebMock, Database Cleaner)'
  task verify_infrastructure: :environment do
    puts "\n=== 🔧 TEST INFRASTRUCTURE VERIFICATION ===\n\n"

    checks = {
      'Database Cleaner' => -> {
        File.exist?(Rails.root.join('spec/support/database_cleaner.rb')) &&
          File.read(Rails.root.join('spec/support/database_cleaner.rb')).include?('DatabaseCleaner')
      },
      'VCR Configuration' => -> {
        File.exist?(Rails.root.join('spec/support/vcr.rb')) &&
          File.read(Rails.root.join('spec/support/vcr.rb')).include?('VCR')
      },
      'WebMock Configuration' => -> {
        File.exist?(Rails.root.join('spec/support/webmock.rb')) &&
          File.read(Rails.root.join('spec/support/webmock.rb')).include?('WebMock')
      },
      'VCR Cassettes Directory' => -> {
        Dir.exist?(Rails.root.join('spec/vcr_cassettes'))
      },
      'RSpec Configuration' => -> {
        File.exist?(Rails.root.join('spec/rails_helper.rb')) &&
          File.exist?(Rails.root.join('spec/spec_helper.rb'))
      },
      'SimpleCov Configuration' => -> {
        File.exist?(Rails.root.join('.simplecov')) ||
          File.read(Rails.root.join('spec/rails_helper.rb')).include?('SimpleCov')
      }
    }

    all_ok = true
    checks.each do |name, check|
      begin
        result = check.call
        status = result ? '✅' : '❌'
        puts "#{status} #{name}"
        all_ok = false unless result
      rescue StandardError => e
        puts "❌ #{name}: #{e.message}"
        all_ok = false
      end
    end

    # Check for VCR cassettes
    puts "\nVCR Cassettes:"
    if Dir.exist?(Rails.root.join('spec/vcr_cassettes'))
      cassette_count = Dir[Rails.root.join('spec/vcr_cassettes/**/*.yml')].count
      puts "   Found #{cassette_count} cassette(s)"
      if cassette_count.zero?
        puts "   ⚠️  No cassettes recorded - run tests with VCR to record API calls"
      end
    else
      puts "   ❌ VCR cassettes directory not found"
      all_ok = false
    end

    puts "\n"
    if all_ok
      puts "✅ Test infrastructure verified\n"
    else
      puts "⚠️  Some infrastructure checks failed\n"
    end
    puts "\n"
  end

  desc 'List all test files'
  task list: :environment do
    puts "\n=== 📋 TEST FILES ===\n\n"
    test_files = Dir[Rails.root.join('spec/**/*_spec.rb')]
    puts "Total test files: #{test_files.count}\n\n"

    test_files.group_by { |f| File.dirname(f).gsub(Rails.root.to_s + '/spec/', '') }.each do |dir, files|
      puts "#{dir}/"
      files.each do |file|
        puts "  - #{File.basename(file)}"
      end
      puts
    end
  end
end

