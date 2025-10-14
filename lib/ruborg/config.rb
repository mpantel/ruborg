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
                  "auto_prune", "hostname", "allow_remove_source", "borg_path", "skip_hash_check")
    end

    private

    VALID_COMPRESSION = %w[lz4 zstd zlib lzma none].freeze
    VALID_ENCRYPTION = %w[repokey keyfile none authenticated repokey-blake2
                          keyfile-blake2 authenticated-blake2].freeze
    VALID_RETENTION_MODES = %w[standard per_file].freeze

    # Valid configuration keys at each level
    VALID_GLOBAL_KEYS = %w[
      hostname compression encryption auto_init auto_prune allow_remove_source
      log_file borg_path passbolt borg_options retention repositories skip_hash_check
    ].freeze

    VALID_REPOSITORY_KEYS = %w[
      name description path hostname retention_mode passbolt retention sources
      compression encryption auto_init auto_prune borg_options allow_remove_source skip_hash_check
    ].freeze

    VALID_SOURCE_KEYS = %w[name paths exclude].freeze

    VALID_RETENTION_KEYS = %w[
      keep_hourly keep_daily keep_weekly keep_monthly keep_yearly
      keep_within keep_last keep_files_modified_within
    ].freeze

    VALID_PASSBOLT_KEYS = %w[resource_id].freeze

    VALID_BORG_OPTIONS_KEYS = %w[allow_relocated_repo allow_unencrypted_repo].freeze

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
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def validate_schema
      errors = []

      # Validate unknown keys
      errors.concat(validate_unknown_keys(@data, VALID_GLOBAL_KEYS, "global"))

      # Validate global boolean settings
      errors.concat(validate_boolean_config(@data, "auto_init", "global"))
      errors.concat(validate_boolean_config(@data, "auto_prune", "global"))
      errors.concat(validate_boolean_config(@data, "allow_remove_source", "global"))
      errors.concat(validate_boolean_config(@data, "skip_hash_check", "global"))

      # NOTE: borg_options are validated as warnings in CLI validate command, not as errors here

      # Validate global passbolt
      errors.concat(validate_passbolt_config(@data["passbolt"], "global")) if @data["passbolt"]

      # Validate global retention
      errors.concat(validate_retention_policy(@data["retention"], "global")) if @data["retention"]

      # Validate compression and encryption if present
      if @data["compression"] && !VALID_COMPRESSION.include?(@data["compression"])
        errors << "global/compression: invalid value '#{@data["compression"]}'"
      end

      if @data["encryption"] && !VALID_ENCRYPTION.include?(@data["encryption"])
        errors << "global/encryption: invalid value '#{@data["encryption"]}'"
      end

      # Validate per-repository settings
      # rubocop:disable Metrics/BlockLength
      repositories.each do |repo|
        repo_name = repo["name"] || "unnamed"

        # Validate unknown keys in repository
        errors.concat(validate_unknown_keys(repo, VALID_REPOSITORY_KEYS, repo_name))

        errors.concat(validate_boolean_config(repo, "auto_init", repo_name))
        errors.concat(validate_boolean_config(repo, "auto_prune", repo_name))
        errors.concat(validate_boolean_config(repo, "allow_remove_source", repo_name))
        errors.concat(validate_boolean_config(repo, "skip_hash_check", repo_name))

        # Validate retention_mode
        if repo["retention_mode"] && !VALID_RETENTION_MODES.include?(repo["retention_mode"])
          errors << "#{repo_name}/retention_mode: invalid value '#{repo["retention_mode"]}'. " \
                    "Must be one of: #{VALID_RETENTION_MODES.join(", ")}"
        end

        # NOTE: borg_options are validated as warnings in CLI validate command, not as errors here

        errors.concat(validate_passbolt_config(repo["passbolt"], repo_name)) if repo["passbolt"]

        errors.concat(validate_retention_policy(repo["retention"], repo_name)) if repo["retention"]

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

        # Validate sources
        next unless repo["sources"].is_a?(Array)

        repo["sources"].each_with_index do |source, idx|
          source_context = "#{repo_name}/sources[#{idx}]"
          source_name = source["name"] || "unnamed"

          errors.concat(validate_unknown_keys(source, VALID_SOURCE_KEYS, "#{repo_name}/sources/#{source_name}"))
          errors << "#{source_context}: missing 'name' key" unless source["name"]
          errors << "#{source_context}: missing 'paths' key" unless source["paths"]
          errors << "#{source_context}: 'paths' must be an array" if source["paths"] && !source["paths"].is_a?(Array)
          if source["exclude"] && !source["exclude"].is_a?(Array)
            errors << "#{source_context}: 'exclude' must be an array"
          end
        end
      end
      # rubocop:enable Metrics/BlockLength

      return if errors.empty?

      raise ConfigError,
            "Configuration validation failed:\n  - #{errors.join("\n  - ")}\n\n" \
            "Run 'ruborg validate' for detailed validation information."
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    def validate_boolean_config(config, key, context)
      errors = []
      value = config[key]

      return errors if value.nil? # Not set is OK

      unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
        errors << "#{context}/#{key}: must be boolean (true or false), got #{value.class}: #{value.inspect}"
      end

      errors
    end

    def validate_unknown_keys(config, valid_keys, context)
      errors = []
      return errors unless config.is_a?(Hash)

      unknown_keys = config.keys - valid_keys
      unknown_keys.each do |key|
        errors << "#{context}: unknown configuration key '#{key}'"
      end

      errors
    end

    def validate_borg_options(borg_options, context)
      errors = []

      unless borg_options.is_a?(Hash)
        errors << "#{context}/borg_options: must be a hash"
        return errors
      end

      errors.concat(validate_unknown_keys(borg_options, VALID_BORG_OPTIONS_KEYS, "#{context}/borg_options"))
      errors.concat(validate_boolean_config(borg_options, "allow_relocated_repo", "#{context}/borg_options"))
      errors.concat(validate_boolean_config(borg_options, "allow_unencrypted_repo", "#{context}/borg_options"))

      errors
    end

    def validate_passbolt_config(passbolt, context)
      errors = []

      unless passbolt.is_a?(Hash)
        errors << "#{context}/passbolt: must be a hash"
        return errors
      end

      errors.concat(validate_unknown_keys(passbolt, VALID_PASSBOLT_KEYS, "#{context}/passbolt"))

      errors << "#{context}/passbolt: missing required 'resource_id' key" unless passbolt["resource_id"]

      if passbolt["resource_id"] && !passbolt["resource_id"].is_a?(String)
        errors << "#{context}/passbolt/resource_id: must be a string"
      end

      if passbolt["resource_id"].is_a?(String) && passbolt["resource_id"].strip.empty?
        errors << "#{context}/passbolt/resource_id: cannot be empty"
      end

      errors
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def validate_retention_policy(retention, context)
      errors = []

      unless retention.is_a?(Hash)
        errors << "#{context}/retention: must be a hash"
        return errors
      end

      errors.concat(validate_unknown_keys(retention, VALID_RETENTION_KEYS, "#{context}/retention"))

      # Validate integer retention values
      %w[keep_hourly keep_daily keep_weekly keep_monthly keep_yearly keep_last].each do |key|
        next unless retention[key]

        unless retention[key].is_a?(Integer) && retention[key] >= 0
          errors << "#{context}/retention/#{key}: must be a non-negative integer, " \
                    "got #{retention[key].class}: #{retention[key].inspect}"
        end
      end

      # Validate time-based retention values (strings)
      %w[keep_within keep_files_modified_within].each do |key|
        next unless retention[key]

        unless retention[key].is_a?(String)
          errors << "#{context}/retention/#{key}: must be a string (e.g., '7d', '30d'), " \
                    "got #{retention[key].class}: #{retention[key].inspect}"
        end

        # Validate time format (e.g., "7d", "30d", "2w", "3m", "1y")
        if retention[key].is_a?(String) && !retention[key].match?(/^\d+[hdwmy]$/)
          errors << "#{context}/retention/#{key}: invalid time format '#{retention[key]}'. " \
                    "Must be a number followed by h/d/w/m/y (e.g., '7d', '30d')"
        end
      end

      # Warn if retention policy is empty
      errors << "#{context}/retention: retention policy is empty" if retention.empty?

      errors
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end
