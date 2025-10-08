# frozen_string_literal: true

require "yaml"
require "psych"

module Ruborg
  # Configuration management for ruborg
  # Only supports multi-repository format
  class Config
    attr_reader :data

    def initialize(config_path)
      @config_path = config_path
      load_config
      validate_format
    end

    def load_config
      raise ConfigError, "Configuration file not found: #{@config_path}" unless File.exist?(@config_path)

      @data = YAML.safe_load_file(@config_path, permitted_classes: [Symbol], aliases: true)
    rescue Psych::SyntaxError => e
      raise ConfigError, "Invalid YAML syntax: #{e.message}"
    rescue Psych::DisallowedClass => e
      raise ConfigError, "Invalid YAML content: #{e.message}"
    end

    def repositories
      @data["repositories"] || []
    end

    def get_repository(name)
      repositories.find { |r| r["name"] == name }
    end

    def repository_names
      repositories.map { |r| r["name"] }
    end

    def global_settings
      @data.slice("passbolt", "compression", "encryption", "auto_init", "borg_options", "log_file", "retention",
                  "auto_prune", "hostname")
    end

    private

    VALID_COMPRESSION = %w[lz4 zstd zlib lzma none].freeze
    VALID_ENCRYPTION = %w[repokey keyfile none authenticated repokey-blake2
                          keyfile-blake2 authenticated-blake2].freeze

    def validate_format
      return if @data.key?("repositories")

      raise ConfigError,
            "Invalid configuration format. Multi-repository format required. See documentation for details."
    end

    def validate_compression(compression)
      unless VALID_COMPRESSION.include?(compression)
        raise ConfigError, "Invalid compression '#{compression}'. Must be one of: #{VALID_COMPRESSION.join(", ")}"
      end

      compression
    end

    def validate_encryption(encryption)
      unless VALID_ENCRYPTION.include?(encryption)
        raise ConfigError, "Invalid encryption mode '#{encryption}'. Must be one of: #{VALID_ENCRYPTION.join(", ")}"
      end

      encryption
    end

    def validate_exclude_patterns(patterns)
      return patterns if patterns.empty?

      patterns.each do |pattern|
        raise ConfigError, "Exclude pattern cannot be empty or nil" if pattern.nil? || pattern.to_s.strip.empty?

        if pattern.length > 1000
          raise ConfigError, "Exclude pattern too long (max 1000 characters): #{pattern[0..50]}..."
        end
      end

      patterns
    end
  end
end
