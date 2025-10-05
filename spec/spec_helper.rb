# frozen_string_literal: true

require "ruborg"
require "fileutils"
require "tmpdir"

# Load support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = "doc" if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed

  # Test fixture helpers
  config.before(:suite) do
    # Create spec/fixtures directory if it doesn't exist
    FileUtils.mkdir_p("spec/fixtures")
  end

  # Temp directory for each test
  config.around(:each) do |example|
    Dir.mktmpdir do |tmpdir|
      @tmpdir = tmpdir
      example.run
    end
  end

  # Helper to get temp directory
  def tmpdir
    @tmpdir
  end

  # Helper to create test files
  def create_test_file(path, content = "test content")
    full_path = File.join(tmpdir, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
    full_path
  end

  # Helper to create test config
  def create_test_config(config_hash)
    config_path = File.join(tmpdir, "test_config.yml")
    File.write(config_path, config_hash.to_yaml)
    config_path
  end
end