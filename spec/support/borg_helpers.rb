# frozen_string_literal: true

# Helper module for borg-related tests
module BorgHelpers
  # Check if borg is installed and available
  def borg_available?
    system("which borg > /dev/null 2>&1")
  end

  # Skip test if borg is not available
  def skip_unless_borg_available
    skip "Borg not installed" unless borg_available?
  end
end

RSpec.configure do |config|
  config.include BorgHelpers

  # Tag tests that require actual borg
  config.before(:each, :borg) do
    skip_unless_borg_available
  end
end
