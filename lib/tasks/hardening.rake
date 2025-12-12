# frozen_string_literal: true

# Helper methods for hardening tasks
module HardeningHelpers
  module_function

  def check_env_vars
    required = %w[DHANHQ_CLIENT_ID DHANHQ_ACCESS_TOKEN]
    missing = required.select { |var| ENV[var].blank? }

    {
      passed: missing.empty?,
      message: missing.empty? ? 'All required vars set' : "Missing: #{missing.join(', ')}"
    }
  end

  def check_database
    ActiveRecord::Base.connection.execute('SELECT 1')
    {
      passed: true,
      message: 'Connected successfully'
    }
  rescue StandardError => e
    {
      passed: false,
      message: "Connection failed: #{e.message}"
    }
  end

  def check_api_credentials
    dhan_ok = ENV['DHANHQ_CLIENT_ID'].present? && ENV['DHANHQ_ACCESS_TOKEN'].present?
    telegram_ok = ENV['TELEGRAM_BOT_TOKEN'].present? && ENV['TELEGRAM_CHAT_ID'].present?
    openai_ok = ENV['OPENAI_API_KEY'].present?

    status = []
    status << 'DhanHQ' if dhan_ok
    status << 'Telegram' if telegram_ok
    status << 'OpenAI' if openai_ok

    {
      passed: dhan_ok, # At least DhanHQ required
      message: "Configured: #{status.join(', ')}"
    }
  end

  def check_secrets_in_code
    # Basic check - look for hardcoded credentials
    found = false
    Dir.glob('app/**/*.rb').each do |file|
      content = File.read(file)
      if content.match?(/password.*=.*['"][^'"]{8,}['"]/i) ||
         content.match?(/api[_-]?key.*=.*['"][^'"]{10,}['"]/i)
        found = true
        break
      end
    end

    {
      passed: !found,
      message: found ? 'Potential secrets found' : 'No secrets in code'
    }
  end

  def check_tests
    # Check if test files exist
    test_files = Dir.glob('spec/**/*_spec.rb')
    {
      passed: test_files.any?,
      message: "#{test_files.size} test files found"
    }
  end

  def check_migrations
    # Rails 8.1+ uses ActiveRecord::MigrationContext directly
    if ActiveRecord::Base.connection.respond_to?(:migration_context)
      pending = ActiveRecord::Base.connection.migration_context.needs_migration?
    else
      # Rails 8.1+ approach
      migration_context = ActiveRecord::MigrationContext.new(Rails.root.join('db', 'migrate'))
      pending = migration_context.needs_migration?
    end
    {
      passed: !pending,
      message: pending ? 'Pending migrations' : 'All migrations applied'
    }
  rescue StandardError => e
    {
      passed: false,
      message: "Migration check failed: #{e.message}"
    }
  end

  def check_configuration
    config_file = Rails.root.join('config', 'algo.yml')
    {
      passed: config_file.exist?,
      message: config_file.exist? ? 'Configuration file exists' : 'Missing config/algo.yml'
    }
  end
end

namespace :hardening do
  desc 'Run pre-production checks'
  task check: :environment do
    puts "🔒 Running Pre-Production Checks"
    puts "=" * 60

    checks = {
      'Environment Variables' => HardeningHelpers.check_env_vars,
      'Database Connection' => HardeningHelpers.check_database,
      'API Credentials' => HardeningHelpers.check_api_credentials,
      'Secrets in Code' => HardeningHelpers.check_secrets_in_code,
      'Test Coverage' => HardeningHelpers.check_tests,
      'Migrations' => HardeningHelpers.check_migrations,
      'Configuration' => HardeningHelpers.check_configuration
    }

    all_passed = true
    checks.each do |name, result|
      status = result[:passed] ? '✅' : '❌'
      puts "#{status} #{name}: #{result[:message]}"
      all_passed = false unless result[:passed]
    end

    puts "=" * 60
    if all_passed
      puts "✅ All checks passed!"
    else
      puts "❌ Some checks failed. Review and fix before production."
      exit 1
    end
  end

  desc 'Check for secrets in code'
  task secrets: :environment do
    puts "🔍 Checking for secrets in code..."

    patterns = [
      /password\s*=\s*['"][^'"]+['"]/i,
      /api[_-]?key\s*=\s*['"][^'"]+['"]/i,
      /token\s*=\s*['"][^'"]+['"]/i,
      /secret\s*=\s*['"][^'"]+['"]/i
    ]

    found = false
    Dir.glob('app/**/*.rb').each do |file|
      next if file.include?('test') || file.include?('spec')

      content = File.read(file)
      patterns.each do |pattern|
        if content.match?(pattern)
          puts "⚠️  Potential secret in #{file}"
          found = true
        end
      end
    end

    if found
      puts "❌ Potential secrets found. Review files above."
      exit 1
    else
      puts "✅ No obvious secrets found in code."
    end
  end

  desc 'Verify database indexes'
  task indexes: :environment do
    puts "📊 Checking database indexes..."

    required_indexes = [
      ['instruments', 'security_id'],
      ['instruments', ['security_id', 'symbol_name', 'exchange', 'segment']],
      ['candle_series', ['instrument_id', 'timeframe', 'timestamp']],
      ['candle_series', ['instrument_id', 'timeframe']],
      ['candle_series', 'timestamp']
    ]

    missing = []
    required_indexes.each do |table, columns|
      columns_array = Array(columns)
      index_name = "index_#{table}_on_#{columns_array.join('_and_')}"

      exists = ActiveRecord::Base.connection.index_exists?(table, columns_array, name: index_name) ||
               ActiveRecord::Base.connection.index_exists?(table, columns_array)

      unless exists
        missing << "#{table}.#{columns_array.join(', ')}"
      end
    end

    if missing.any?
      puts "❌ Missing indexes:"
      missing.each { |idx| puts "   - #{idx}" }
      exit 1
    else
      puts "✅ All required indexes present."
    end
  end
end


