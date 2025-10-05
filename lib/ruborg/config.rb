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

      @data = YAML.safe_load_file(@config_path, permitted_classes: [Symbol], aliases: true)
    rescue Psych::SyntaxError => e
      raise ConfigError, "Invalid YAML syntax: #{e.message}"
    rescue Psych::DisallowedClass => e
      raise ConfigError, "Invalid YAML content: #{e.message}"
    end

    # Legacy single-repo accessors (for backward compatibility)
    def repository
      @data["repository"]
    end

    def backup_paths
      @data["backup_paths"] || []
    end

    def exclude_patterns
      patterns = @data["exclude_patterns"] || []
      validate_exclude_patterns(patterns)
    end

    def compression
      value = @data["compression"] || "lz4"
      validate_compression(value)
    end

    def encryption_mode
      value = @data["encryption"] || "repokey"
      validate_encryption(value)
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

    def borg_options
      @data["borg_options"] || {}
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

    VALID_COMPRESSION = ["lz4", "zstd", "zlib", "lzma", "none"].freeze
    VALID_ENCRYPTION = ["repokey", "keyfile", "none", "authenticated", "repokey-blake2",
                        "keyfile-blake2", "authenticated-blake2"].freeze

    def detect_format
      @multi_repo = @data.key?("repositories")
    end

    def validate_compression(compression)
      unless VALID_COMPRESSION.include?(compression)
        raise ConfigError, "Invalid compression '#{compression}'. Must be one of: #{VALID_COMPRESSION.join(', ')}"
      end
      compression
    end

    def validate_encryption(encryption)
      unless VALID_ENCRYPTION.include?(encryption)
        raise ConfigError, "Invalid encryption mode '#{encryption}'. Must be one of: #{VALID_ENCRYPTION.join(', ')}"
      end
      encryption
    end

    def validate_exclude_patterns(patterns)
      return patterns if patterns.empty?

      patterns.each do |pattern|
        if pattern.nil? || pattern.to_s.strip.empty?
          raise ConfigError, "Exclude pattern cannot be empty or nil"
        end

        if pattern.length > 1000
          raise ConfigError, "Exclude pattern too long (max 1000 characters): #{pattern[0..50]}..."
        end
      end

      patterns
    end
  end
end