# frozen_string_literal: true

require_relative "ruborg/version"
require_relative "ruborg/logger"
require_relative "ruborg/config"
require_relative "ruborg/repository"
require_relative "ruborg/backup"
require_relative "ruborg/passbolt"
require_relative "ruborg/cli"

module Ruborg
  class Error < StandardError; end
  class ConfigError < Error; end
  class BorgError < Error; end
  class PassboltError < Error; end
end