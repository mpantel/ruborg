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
      detect_format
    end

    def load_config
      raise ConfigError, "Configuration file not found: #{@config_path}" unless File.exist?(@config_path)

      @data = YAML.load_file(@config_path)
    rescue Psych::SyntaxError => e
      raise ConfigError, "Invalid YAML syntax: #{e.message}"
    end

    # Legacy single-repo accessors (for backward compatibility)
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

    def auto_init?
      @data["auto_init"] || false
    end

    def log_file
      @data["log_file"]
    end

    # New multi-repo support
    def multi_repo?
      @multi_repo
    end

    def repositories
      return [] unless multi_repo?
      @data["repositories"] || []
    end

    def get_repository(name)
      return nil unless multi_repo?
      repositories.find { |r| r["name"] == name }
    end

    def repository_names
      return [] unless multi_repo?
      repositories.map { |r| r["name"] }
    end

    def global_settings
      @data.slice("passbolt", "compression", "encryption", "auto_init")
    end

    private

    def detect_format
      @multi_repo = @data.key?("repositories")
    end
  end
end