# SimpleCov configuration
# This file is loaded by SimpleCov when running tests

SimpleCov.configure do
  # Output format
  formatter SimpleCov::Formatter::HTMLFormatter

  # Coverage directory
  coverage_dir 'coverage'

  # Track all files
  track_files '{app,lib}/**/*.rb'

  # Exclude files from coverage
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/vendor/'
  add_filter '/db/'
  add_filter '/lib/tasks/'
  add_filter '/test/'

  # Minimum coverage percentage
  # Target: 90% test coverage for all implementations
  # Can be overridden via MINIMUM_COVERAGE environment variable for local development
  minimum_coverage (ENV['MINIMUM_COVERAGE'] || 90).to_i
end

