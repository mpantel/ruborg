# frozen_string_literal: true

require "yaml"
require "psych"

module Ruborg
  # Configuration management for ruborg
  class Config
    attr_reader :data

    def initialize(config_path)
      @config_path = config_path
      load_config
    end

    def load_config
      raise ConfigError, "Configuration file not found: #{@config_path}" unless File.exist?(@config_path)

      @data = YAML.load_file(@config_path)
    rescue Psych::SyntaxError => e
      raise ConfigError, "Invalid YAML syntax: #{e.message}"
    end

    def repository
      @data["repository"]
    end

    def backup_paths
      @data["backup_paths"] || []
    end

    def exclude_patterns
      @data["exclude_patterns"] || []
    end

    def compression
      @data["compression"] || "lz4"
    end

    def encryption_mode
      @data["encryption"] || "repokey"
    end

    def passbolt_integration
      @data["passbolt"] || {}
    end
  end
end