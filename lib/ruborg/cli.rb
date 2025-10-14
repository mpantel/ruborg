# frozen_string_literal: true

require "thor"

module Ruborg
  # Command-line interface for ruborg
  class CLI < Thor
    class_option :config, type: :string, default: "ruborg.yml", desc: "Path to configuration file"
    class_option :log, type: :string, desc: "Path to log file"
    class_option :repository, type: :string, aliases: "-r", desc: "Repository name (for multi-repo configs)"

    def initialize(*args)
      super
      # Priority: CLI option > config file > default
      log_path = options[:log]
      unless log_path
        # Try to load config to get log_file setting
        config_path = options[:config] || "ruborg.yml"
        if File.exist?(config_path)
          config_data = begin
            YAML.safe_load_file(config_path, permitted_classes: [Symbol], aliases: true)
          rescue StandardError
            {}
          end
          log_path = config_data["log_file"]
        end
      end

      # Validate log path if provided
      log_path = validate_log_path(log_path) if log_path

      @logger = RuborgLogger.new(log_file: log_path)
    end

    desc "init REPOSITORY", "Initialize a new Borg repository"
    option :passphrase, type: :string, desc: "Repository passphrase"
    option :passbolt_id, type: :string, desc: "Passbolt resource ID for passphrase"
    def init(repository_path)
      @logger.info("Initializing repository at #{repository_path}")
      passphrase = get_passphrase(options[:passphrase], options[:passbolt_id])
      repo = Repository.new(repository_path, passphrase: passphrase, logger: @logger)
      repo.create
      @logger.info("Repository successfully initialized at #{repository_path}")
      puts "Repository initialized at #{repository_path}"
    rescue Error => e
      @logger.error("Failed to initialize repository: #{e.message}")
      raise
    end

    desc "backup", "Create a backup using configuration file"
    option :name, type: :string, desc: "Archive name"
    option :remove_source, type: :boolean, default: false, desc: "Remove source files after successful backup"
    option :all, type: :boolean, default: false, desc: "Backup all repositories"
    def backup
      @logger.info("Starting backup operation with config: #{options[:config]}")
      config = Config.new(options[:config])
      backup_repositories(config)
    rescue Error => e
      @logger.error("Backup failed: #{e.message}")
      raise
    end

    desc "list", "List all archives in the repository or files in a specific archive"
    option :archive, type: :string, desc: "Archive name to list files from"
    def list
      config = Config.new(options[:config])

      raise ConfigError, "Please specify --repository" unless options[:repository]

      repo_config = config.get_repository(options[:repository])
      raise ConfigError, "Repository '#{options[:repository]}' not found" unless repo_config

      global_settings = config.global_settings
      merged_config = global_settings.merge(repo_config)
      validate_hostname(merged_config)
      passphrase = fetch_passphrase_for_repo(merged_config)
      borg_opts = merged_config["borg_options"] || {}
      borg_path = merged_config["borg_path"]

      repo = Repository.new(repo_config["path"], passphrase: passphrase, borg_options: borg_opts, borg_path: borg_path,
                                                 logger: @logger)

      # Auto-initialize repository if configured
      # Use strict boolean checking: only true enables, everything else disables
      auto_init = merged_config["auto_init"]
      auto_init = false unless auto_init == true
      if auto_init && !repo.exists?
        @logger.info("Auto-initializing repository at #{repo_config["path"]}")
        repo.create
        puts "Repository auto-initialized at #{repo_config["path"]}"
      end

      if options[:archive]
        @logger.info("Listing files in archive: #{options[:archive]}")
        repo.list_archive(options[:archive])
        @logger.info("Successfully listed files in archive")
      else
        @logger.info("Listing archives in repository")
        repo.list
        @logger.info("Successfully listed archives")
      end
    rescue Error => e
      @logger.error("Failed to list: #{e.message}")
      raise
    end

    desc "restore ARCHIVE", "Restore files from an archive"
    option :destination, type: :string, default: ".", desc: "Destination directory"
    option :path, type: :string, desc: "Specific file or directory path to restore from archive"
    def restore(archive_name)
      restore_target = options[:path] ? "#{options[:path]} from #{archive_name}" : archive_name
      @logger.info("Restoring #{restore_target} to #{options[:destination]}")
      config = Config.new(options[:config])

      raise ConfigError, "Please specify --repository" unless options[:repository]

      repo_config = config.get_repository(options[:repository])
      raise ConfigError, "Repository '#{options[:repository]}' not found" unless repo_config

      global_settings = config.global_settings
      merged_config = global_settings.merge(repo_config)
      validate_hostname(merged_config)
      passphrase = fetch_passphrase_for_repo(merged_config)
      borg_opts = merged_config["borg_options"] || {}
      borg_path = merged_config["borg_path"]

      repo = Repository.new(repo_config["path"], passphrase: passphrase, borg_options: borg_opts, borg_path: borg_path,
                                                 logger: @logger)

      # Create backup config wrapper for compatibility
      backup_config = BackupConfig.new(repo_config, merged_config)
      backup = Backup.new(repo, config: backup_config, logger: @logger)

      backup.extract(archive_name, destination: options[:destination], path: options[:path])
      @logger.info("Successfully restored #{restore_target} to #{options[:destination]}")

      if options[:path]
        puts "Restored #{options[:path]} from #{archive_name} to #{options[:destination]}"
      else
        puts "Archive restored to #{options[:destination]}"
      end
    rescue Error => e
      @logger.error("Failed to restore archive: #{e.message}")
      raise
    end

    desc "info", "Show repository information"
    def info
      @logger.info("Retrieving repository information")
      config = Config.new(options[:config])

      # If no repository specified, show summary of all repositories
      unless options[:repository]
        show_repositories_summary(config)
        return
      end

      repo_config = config.get_repository(options[:repository])
      raise ConfigError, "Repository '#{options[:repository]}' not found" unless repo_config

      global_settings = config.global_settings
      merged_config = global_settings.merge(repo_config)
      passphrase = fetch_passphrase_for_repo(merged_config)
      borg_opts = merged_config["borg_options"] || {}
      borg_path = merged_config["borg_path"]

      repo = Repository.new(repo_config["path"], passphrase: passphrase, borg_options: borg_opts, borg_path: borg_path,
                                                 logger: @logger)

      # Auto-initialize repository if configured
      # Use strict boolean checking: only true enables, everything else disables
      auto_init = merged_config["auto_init"]
      auto_init = false unless auto_init == true
      if auto_init && !repo.exists?
        @logger.info("Auto-initializing repository at #{repo_config["path"]}")
        repo.create
        puts "Repository auto-initialized at #{repo_config["path"]}"
      end

      repo.info
      @logger.info("Successfully retrieved repository information")
    rescue Error => e
      @logger.error("Failed to get repository info: #{e.message}")
      raise
    end

    desc "validate TYPE", "Validate configuration file or repository (TYPE: config or repo)"
    option :verify_data, type: :boolean, default: false, desc: "Verify repository data (slower, only for 'repo' type)"
    option :all, type: :boolean, default: false, desc: "Validate all repositories (only for 'repo' type)"
    def validate(type)
      case type
      when "config"
        validate_config_implementation
      when "repo"
        validate_repo_implementation
      else
        raise ConfigError, "Invalid validation type: #{type}. Use 'config' or 'repo'"
      end
    end

    private

    def validate_config_implementation
      @logger.info("Validating configuration file: #{options[:config]}")
      config = Config.new(options[:config])

      puts "\n═══════════════════════════════════════════════════════════════"
      puts "  CONFIGURATION VALIDATION"
      puts "═══════════════════════════════════════════════════════════════\n\n"

      errors = []
      warnings = []

      # Validate global boolean settings
      global_settings = config.global_settings
      errors.concat(validate_boolean_setting(global_settings, "auto_init", "global"))
      errors.concat(validate_boolean_setting(global_settings, "auto_prune", "global"))
      errors.concat(validate_boolean_setting(global_settings, "allow_remove_source", "global"))
      errors.concat(validate_boolean_setting(global_settings, "skip_hash_check", "global"))

      # Validate borg_options booleans
      if global_settings["borg_options"]
        warnings.concat(validate_borg_option(global_settings["borg_options"], "allow_relocated_repo", "global"))
        warnings.concat(validate_borg_option(global_settings["borg_options"], "allow_unencrypted_repo", "global"))
      end

      # Validate per-repository settings
      config.repositories.each do |repo|
        repo_name = repo["name"]
        errors.concat(validate_boolean_setting(repo, "auto_init", repo_name))
        errors.concat(validate_boolean_setting(repo, "auto_prune", repo_name))
        errors.concat(validate_boolean_setting(repo, "allow_remove_source", repo_name))
        errors.concat(validate_boolean_setting(repo, "skip_hash_check", repo_name))

        if repo["borg_options"]
          warnings.concat(validate_borg_option(repo["borg_options"], "allow_relocated_repo", repo_name))
          warnings.concat(validate_borg_option(repo["borg_options"], "allow_unencrypted_repo", repo_name))
        end
      end

      # Display results
      if errors.empty? && warnings.empty?
        puts "✓ Configuration is valid"
        puts "  No type errors or warnings found\n\n"
      else
        unless errors.empty?
          puts "❌ ERRORS FOUND (#{errors.size}):"
          errors.each do |error|
            puts "  - #{error}"
          end
          puts ""
        end

        unless warnings.empty?
          puts "⚠️  WARNINGS (#{warnings.size}):"
          warnings.each do |warning|
            puts "  - #{warning}"
          end
          puts ""
        end

        if errors.any?
          puts "Configuration has errors that must be fixed.\n\n"
          @logger.error("Configuration validation failed")
          exit 1
        else
          puts "Configuration is valid but has warnings.\n\n"
        end
      end

      @logger.info("Configuration validation completed")
    rescue Error => e
      @logger.error("Validation failed: #{e.message}")
      raise
    end

    def validate_repo_implementation
      @logger.info("Validating repository compatibility")
      config = Config.new(options[:config])
      global_settings = config.global_settings
      validate_hostname(global_settings)

      # Show Borg version first
      borg_version = Repository.borg_version
      puts "\nBorg version: #{borg_version}\n\n"

      repos_to_validate = if options[:all]
                            config.repositories
                          elsif options[:repository]
                            repo_config = config.get_repository(options[:repository])
                            raise ConfigError, "Repository '#{options[:repository]}' not found" unless repo_config

                            [repo_config]
                          else
                            raise ConfigError, "Please specify --repository or --all"
                          end

      repos_to_validate.each do |repo_config|
        validate_repository(repo_config, global_settings)
      end
    rescue Error => e
      @logger.error("Validation failed: #{e.message}")
      raise
    end

    def validate_repository(repo_config, global_settings)
      repo_name = repo_config["name"]
      puts "--- Validating repository: #{repo_name} ---"
      @logger.info("Validating repository: #{repo_name}")

      merged_config = global_settings.merge(repo_config)
      validate_hostname(merged_config)
      passphrase = fetch_passphrase_for_repo(merged_config)
      borg_opts = merged_config["borg_options"] || {}
      borg_path = merged_config["borg_path"]

      repo = Repository.new(repo_config["path"], passphrase: passphrase, borg_options: borg_opts, borg_path: borg_path,
                                                 logger: @logger)

      unless repo.exists?
        puts "  ✗ Repository does not exist at #{repo_config["path"]}"
        @logger.error("Repository does not exist: #{repo_name}")
        puts ""
        return
      end

      # Check compatibility
      compatibility = repo.check_compatibility
      puts "  Repository version: #{compatibility[:repository_version]}"

      if compatibility[:compatible]
        puts "  ✓ Compatible with Borg #{compatibility[:borg_version]}"
        @logger.info("Repository #{repo_name} is compatible")
      else
        puts "  ✗ INCOMPATIBLE with Borg #{compatibility[:borg_version]}"
        repo_ver = compatibility[:repository_version]
        borg_ver = compatibility[:borg_version]
        puts "    Repository version #{repo_ver} cannot be read by Borg #{borg_ver}"
        puts "    Please upgrade Borg or migrate the repository"
        @logger.error("Repository #{repo_name} is incompatible with installed Borg version")
      end

      # Run integrity check if requested
      if options[:verify_data]
        puts "  Running integrity check..."
        @logger.info("Running integrity check on #{repo_name}")
        repo.check
        puts "  ✓ Integrity check passed"
        @logger.info("Integrity check passed for #{repo_name}")
      end

      puts ""
    rescue BorgError => e
      puts "  ✗ Validation failed: #{e.message}"
      @logger.error("Validation failed for #{repo_name}: #{e.message}")
      puts ""
    end

    public

    desc "version", "Show ruborg and borg versions"
    def version
      require_relative "version"
      puts "ruborg #{Ruborg::VERSION}"
      @logger.info("Version checked: #{Ruborg::VERSION}")

      begin
        borg_version = Repository.borg_version
        borg_path = Repository.borg_path
        puts "borg #{borg_version} (#{borg_path})"
        @logger.info("Borg version: #{borg_version}, path: #{borg_path}")
      rescue BorgError => e
        puts "borg: not found or not executable"
        @logger.warn("Could not determine Borg version: #{e.message}")
      end
    end

    desc "check", "DEPRECATED: Use 'ruborg validate repo' instead"
    option :verify_data, type: :boolean, default: false, desc: "Verify repository data (slower)"
    option :all, type: :boolean, default: false, desc: "Validate all repositories"
    def check
      puts "\n⚠️  DEPRECATED COMMAND"
      puts "══════════════════════════════════════════════════════════════════\n\n"
      puts "The 'ruborg check' command has been renamed for consistency.\n"
      puts "Please use: ruborg validate repo\n\n"
      puts "Examples:"
      puts "  ruborg validate repo --repository documents"
      puts "  ruborg validate repo --all"
      puts "  ruborg validate repo --repository documents --verify-data\n\n"
      puts "══════════════════════════════════════════════════════════════════\n"

      @logger.warn("Deprecated command 'check' was called. User should use 'validate repo' instead.")
      exit 1
    end

    desc "metadata ARCHIVE", "Get file metadata from an archive"
    option :file, type: :string, desc: "Specific file path (required for standard archives, auto for per-file)"
    def metadata(archive_name)
      @logger.info("Getting metadata for archive: #{archive_name}")
      config = Config.new(options[:config])

      raise ConfigError, "Please specify --repository" unless options[:repository]

      repo_config = config.get_repository(options[:repository])
      raise ConfigError, "Repository '#{options[:repository]}' not found" unless repo_config

      global_settings = config.global_settings
      merged_config = global_settings.merge(repo_config)
      validate_hostname(merged_config)
      passphrase = fetch_passphrase_for_repo(merged_config)
      borg_opts = merged_config["borg_options"] || {}
      borg_path = merged_config["borg_path"]

      repo = Repository.new(repo_config["path"], passphrase: passphrase, borg_options: borg_opts, borg_path: borg_path,
                                                 logger: @logger)

      raise BorgError, "Repository does not exist at #{repo_config["path"]}" unless repo.exists?

      # Get file metadata
      metadata = repo.get_file_metadata(archive_name, file_path: options[:file])

      # Display metadata
      puts "\n═══════════════════════════════════════════════════════════════"
      puts "  FILE METADATA"
      puts "═══════════════════════════════════════════════════════════════\n\n"
      puts "Archive: #{archive_name}"
      puts "File: #{metadata["path"]}"
      puts "Size: #{format_size(metadata["size"])}"
      puts "Modified: #{metadata["mtime"]}"
      puts "Mode: #{metadata["mode"]}"
      puts "User: #{metadata["user"]}"
      puts "Group: #{metadata["group"]}"
      puts "Type: #{metadata["type"]}"
      puts ""

      @logger.info("Successfully retrieved metadata for #{metadata["path"]}")
    rescue Error => e
      @logger.error("Failed to get metadata: #{e.message}")
      raise
    end

    private

    def show_repositories_summary(config)
      repositories = config.repositories
      global_settings = config.global_settings

      if repositories.empty?
        puts "No repositories configured."
        return
      end

      puts "\n═══════════════════════════════════════════════════════════════"
      puts "  RUBORG REPOSITORIES SUMMARY"
      puts "═══════════════════════════════════════════════════════════════\n\n"

      # Show global settings
      puts "Global Settings:"
      puts "  Hostname:       #{global_settings["hostname"]}" if global_settings["hostname"]
      puts "  Compression:    #{global_settings["compression"] || "lz4 (default)"}"
      puts "  Encryption:     #{global_settings["encryption"] || "repokey (default)"}"
      puts "  Auto-init:      #{global_settings["auto_init"] || false}"
      puts "  Retention:      #{format_retention(global_settings["retention"])}" if global_settings["retention"]
      puts ""

      puts "Configured Repositories (#{repositories.size}):"
      puts "─────────────────────────────────────────────────────────────────\n\n"

      repositories.each_with_index do |repo, index|
        merged_config = global_settings.merge(repo)

        puts "#{index + 1}. #{repo["name"]}"
        puts "   Path:        #{repo["path"]}"
        puts "   Description: #{repo["description"]}" if repo["description"]

        # Show repo-specific overrides
        puts "   Hostname:    #{repo["hostname"]}" if repo["hostname"]
        puts "   Compression: #{repo["compression"]}" if repo["compression"]
        puts "   Encryption:  #{repo["encryption"]}" if repo["encryption"]
        puts "   Auto-init:   #{repo["auto_init"]}" unless repo["auto_init"].nil?
        if repo["retention"]
          puts "   Retention:   #{format_retention(repo["retention"])}"
        elsif merged_config["retention"]
          puts "   Retention:   #{format_retention(merged_config["retention"])} (global)"
        end

        # Show sources
        sources = repo["sources"] || []
        puts "   Sources (#{sources.size}):"
        sources.each do |source|
          paths = source["paths"] || []
          puts "     - #{source["name"]}: #{paths.size} path(s)"
        end

        puts ""
      end

      puts "─────────────────────────────────────────────────────────────────"
      puts "Use 'ruborg info --repository NAME' for detailed information\n\n"
    end

    def format_retention(retention)
      return "none" if retention.nil? || retention.empty?

      parts = []
      # Count-based retention
      parts << "#{retention["keep_hourly"]}h" if retention["keep_hourly"]
      parts << "#{retention["keep_daily"]}d" if retention["keep_daily"]
      parts << "#{retention["keep_weekly"]}w" if retention["keep_weekly"]
      parts << "#{retention["keep_monthly"]}m" if retention["keep_monthly"]
      parts << "#{retention["keep_yearly"]}y" if retention["keep_yearly"]

      # Time-based retention
      parts << "within #{retention["keep_within"]}" if retention["keep_within"]
      parts << "last #{retention["keep_last"]}" if retention["keep_last"]

      parts.empty? ? "none" : parts.join(", ")
    end

    def format_size(bytes)
      return "0 B" if bytes.nil? || bytes.zero?

      units = %w[B KB MB GB TB]
      size = bytes.to_f
      unit_index = 0

      while size >= 1024 && unit_index < units.length - 1
        size /= 1024.0
        unit_index += 1
      end

      format("%.2f %s", size, units[unit_index])
    end

    def get_passphrase(passphrase, passbolt_id)
      return passphrase if passphrase
      return Passbolt.new(resource_id: passbolt_id, logger: @logger).get_password if passbolt_id

      nil
    end

    def validate_log_path(log_path)
      # Expand to absolute path
      normalized_path = File.expand_path(log_path)

      # Prevent writing to sensitive system directories
      forbidden_paths = ["/bin", "/sbin", "/usr/bin", "/usr/sbin", "/etc", "/sys", "/proc", "/boot"]
      forbidden_paths.each do |forbidden|
        if normalized_path.start_with?("#{forbidden}/")
          raise ConfigError, "Invalid log path: refusing to write to system directory #{normalized_path}"
        end
      end

      # Ensure parent directory exists or can be created
      log_dir = File.dirname(normalized_path)
      unless File.directory?(log_dir)
        begin
          FileUtils.mkdir_p(log_dir)
        rescue StandardError => e
          raise ConfigError, "Cannot create log directory #{log_dir}: #{e.message}"
        end
      end

      normalized_path
    end

    # Backup repositories based on options
    def backup_repositories(config)
      global_settings = config.global_settings
      repos_to_backup = if options[:all]
                          config.repositories
                        elsif options[:repository]
                          repo_config = config.get_repository(options[:repository])
                          raise ConfigError, "Repository '#{options[:repository]}' not found" unless repo_config

                          [repo_config]
                        else
                          raise ConfigError, "Please specify --repository or --all"
                        end

      repos_to_backup.each do |repo_config|
        backup_repository(repo_config, global_settings)
      end
    end

    def backup_repository(repo_config, global_settings)
      repo_name = repo_config["name"]
      puts "\n--- Backing up repository: #{repo_name} ---"
      @logger.info("Backing up repository: #{repo_name}")

      # Merge global settings with repo-specific settings (repo-specific takes precedence)
      merged_config = global_settings.merge(repo_config)
      validate_hostname(merged_config)

      passphrase = fetch_passphrase_for_repo(merged_config)
      borg_opts = merged_config["borg_options"] || {}
      borg_path = merged_config["borg_path"]
      repo = Repository.new(repo_config["path"], passphrase: passphrase, borg_options: borg_opts, borg_path: borg_path,
                                                 logger: @logger)

      # Auto-initialize if configured
      # Use strict boolean checking: only true enables, everything else disables
      auto_init = merged_config["auto_init"]
      auto_init = false unless auto_init == true
      if auto_init && !repo.exists?
        @logger.info("Auto-initializing repository at #{repo_config["path"]}")
        repo.create
        puts "Repository auto-initialized at #{repo_config["path"]}"
      end

      # Get retention mode (defaults to standard)
      retention_mode = merged_config["retention_mode"] || "standard"

      # Validate remove_source permission with strict type checking
      if options[:remove_source]
        allow_remove_source = merged_config["allow_remove_source"]
        unless allow_remove_source.is_a?(TrueClass)
          raise ConfigError,
                "Cannot use --remove-source: 'allow_remove_source' must be true (boolean). " \
                "Current value: #{allow_remove_source.inspect} (#{allow_remove_source.class}). " \
                "Set 'allow_remove_source: true' in configuration to allow source deletion."
        end
      end

      # Get skip_hash_check setting (defaults to false)
      skip_hash_check = merged_config["skip_hash_check"]
      skip_hash_check = false unless skip_hash_check == true

      # Create backup config wrapper
      backup_config = BackupConfig.new(repo_config, merged_config)
      backup = Backup.new(repo, config: backup_config, retention_mode: retention_mode, repo_name: repo_name,
                                logger: @logger, skip_hash_check: skip_hash_check)

      archive_name = options[:name] ? sanitize_archive_name(options[:name]) : nil
      @logger.info("Creating archive#{"s" if retention_mode == "per_file"}: #{archive_name || "auto-generated"}")

      sources = repo_config["sources"] || []
      @logger.info("Backing up #{sources.size} source(s)#{" in per-file mode" if retention_mode == "per_file"}")

      backup.create(name: archive_name, remove_source: options[:remove_source])
      @logger.info("Backup created successfully")

      if retention_mode == "per_file"
        puts "✓ Per-file backups created"
      else
        puts "✓ Backup created: #{archive_name || "auto-generated"}"
      end
      puts "  Sources removed" if options[:remove_source]

      # Auto-prune if configured and retention policy exists
      # Use strict boolean checking: only true enables, everything else disables
      auto_prune = merged_config["auto_prune"]
      auto_prune = false unless auto_prune == true
      retention_policy = merged_config["retention"]

      return unless auto_prune && retention_policy && !retention_policy.empty?

      mode_desc = retention_mode == "per_file" ? "per-file mode" : "standard mode"
      @logger.info("Auto-pruning repository: #{repo_name} (#{mode_desc})")
      puts "  Pruning old backups (#{mode_desc})..."
      repo.prune(retention_policy, retention_mode: retention_mode)
      @logger.info("Pruning completed successfully for #{repo_name}")
      puts "  ✓ Pruning completed"
    end

    def fetch_passphrase_for_repo(repo_config)
      passbolt_config = repo_config["passbolt"]
      return nil if passbolt_config.nil? || passbolt_config.empty?

      Passbolt.new(resource_id: passbolt_config["resource_id"], logger: @logger).get_password
    end

    def sanitize_archive_name(name)
      raise ConfigError, "Archive name cannot be empty" if name.nil? || name.strip.empty?

      # Check if name contains at least one valid character before sanitization
      unless name =~ /[a-zA-Z0-9._-]/
        raise ConfigError,
              "Invalid archive name: must contain at least one valid character (alphanumeric, dot, dash, or underscore)"
      end

      # Allow only alphanumeric, dash, underscore, and dot
      name.gsub(/[^a-zA-Z0-9._-]/, "_")
    end

    def validate_hostname(config)
      configured_hostname = config["hostname"]
      return if configured_hostname.nil? || configured_hostname.empty?

      current_hostname = `hostname`.strip
      return if current_hostname == configured_hostname

      raise ConfigError,
            "Hostname mismatch: configuration is for '#{configured_hostname}' " \
            "but current hostname is '#{current_hostname}'"
    end

    # Validate boolean configuration settings
    def validate_boolean_setting(config, key, context)
      errors = []
      value = config[key]

      return errors if value.nil? # Not set is OK

      unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
        errors << "#{context}/#{key}: must be boolean (true/false), got #{value.class}: #{value.inspect}"
      end

      errors
    end

    # Validate borg_options boolean settings (these have different defaults)
    def validate_borg_option(borg_options, key, context)
      warnings = []
      value = borg_options[key]

      return warnings if value.nil? # Not set is OK (uses default)

      unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
        warnings << "#{context}/borg_options/#{key}: should be boolean (true/false), got #{value.class}: #{value.inspect}"
      end

      warnings
    end

    # Wrapper class to adapt repository config to existing Backup class
    class BackupConfig
      def initialize(repo_config, merged_settings)
        @repo_config = repo_config
        @merged_settings = merged_settings
      end

      def backup_paths
        sources = @repo_config["sources"] || []
        sources.flat_map do |source|
          source["paths"] || []
        end
      end

      def exclude_patterns
        patterns = []
        sources = @repo_config["sources"] || []
        sources.each do |source|
          patterns += source["exclude"] || []
        end
        patterns += @merged_settings["exclude_patterns"] || []
        patterns.uniq
      end

      def compression
        @merged_settings["compression"] || "lz4"
      end

      def encryption_mode
        @merged_settings["encryption"] || "repokey"
      end
    end
  end
end
