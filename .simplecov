# SimpleCov configuration
# This file is loaded by SimpleCov when running tests

SimpleCov.configure do
  # Output format
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::SimpleFormatter,
    SimpleCov::Formatter::HTMLFormatter
  ])

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
  minimum_coverage 80

  # Refuse to exit with non-zero status when minimum coverage is not met
  # Set to false to allow tests to pass even if coverage is below threshold
  refuse_coverage_drop false
end

