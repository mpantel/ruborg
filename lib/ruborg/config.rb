# frozen_string_literal: true

require "yaml"
require "psych"

module Ruborg
  # Configuration management for ruborg
  # Only supports multi-repository format
  class Config
    attr_reader :data

    def initialize(config_path, validate_types: true)
      @config_path = config_path
      @validate_types = validate_types
      load_config
      validate_format
      validate_schema if @validate_types
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
                  "auto_prune", "hostname", "allow_remove_source")
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

    # Validate YAML schema for type correctness
    def validate_schema
      errors = []

      # Validate global boolean settings
      errors.concat(validate_boolean_config(@data, "auto_init", "global"))
      errors.concat(validate_boolean_config(@data, "auto_prune", "global"))
      errors.concat(validate_boolean_config(@data, "allow_remove_source", "global"))

      # Validate global borg_options
      if @data["borg_options"]
        errors.concat(validate_boolean_config(@data["borg_options"], "allow_relocated_repo", "global/borg_options"))
        errors.concat(validate_boolean_config(@data["borg_options"], "allow_unencrypted_repo", "global/borg_options"))
      end

      # Validate compression and encryption if present
      if @data["compression"] && !VALID_COMPRESSION.include?(@data["compression"])
        errors << "global/compression: invalid value '#{@data["compression"]}'"
      end

      if @data["encryption"] && !VALID_ENCRYPTION.include?(@data["encryption"])
        errors << "global/encryption: invalid value '#{@data["encryption"]}'"
      end

      # Validate per-repository settings
      repositories.each do |repo|
        repo_name = repo["name"] || "unnamed"

        errors.concat(validate_boolean_config(repo, "auto_init", repo_name))
        errors.concat(validate_boolean_config(repo, "auto_prune", repo_name))
        errors.concat(validate_boolean_config(repo, "allow_remove_source", repo_name))

        if repo["borg_options"]
          errors.concat(validate_boolean_config(repo["borg_options"], "allow_relocated_repo",
                                                "#{repo_name}/borg_options"))
          errors.concat(validate_boolean_config(repo["borg_options"], "allow_unencrypted_repo",
                                                "#{repo_name}/borg_options"))
        end

        # Validate compression and encryption if present
        if repo["compression"] && !VALID_COMPRESSION.include?(repo["compression"])
          errors << "#{repo_name}/compression: invalid value '#{repo["compression"]}'"
        end

        if repo["encryption"] && !VALID_ENCRYPTION.include?(repo["encryption"])
          errors << "#{repo_name}/encryption: invalid value '#{repo["encryption"]}'"
        end

        # Validate repository structure
        errors << "#{repo_name}: missing 'path' key" unless repo["path"]
        errors << "#{repo_name}: 'sources' must be an array" if repo["sources"] && !repo["sources"].is_a?(Array)
      end

      return if errors.empty?

      raise ConfigError,
            "Configuration validation failed:\n  - #{errors.join("\n  - ")}\n\n" \
            "Run 'ruborg validate' for detailed validation information."
    end

    def validate_boolean_config(config, key, context)
      errors = []
      value = config[key]

      return errors if value.nil? # Not set is OK

      unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
        errors << "#{context}/#{key}: must be boolean (true or false), got #{value.class}: #{value.inspect}"
      end

      errors
    end
  end
end
