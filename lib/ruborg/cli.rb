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
          config_data = YAML.load_file(config_path) rescue {}
          log_path = config_data["log_file"]
        end
      end
      @logger = RuborgLogger.new(log_file: log_path)
    end

    desc "init REPOSITORY", "Initialize a new Borg repository"
    option :passphrase, type: :string, desc: "Repository passphrase"
    option :passbolt_id, type: :string, desc: "Passbolt resource ID for passphrase"
    def init(repository_path)
      @logger.info("Initializing repository at #{repository_path}")
      passphrase = get_passphrase(options[:passphrase], options[:passbolt_id])
      repo = Repository.new(repository_path, passphrase: passphrase)
      repo.create
      @logger.info("Repository successfully initialized at #{repository_path}")
      puts "Repository initialized at #{repository_path}"
    rescue Error => e
      @logger.error("Failed to initialize repository: #{e.message}")
      error_exit(e)
    end

    desc "backup", "Create a backup using configuration file"
    option :name, type: :string, desc: "Archive name"
    option :remove_source, type: :boolean, default: false, desc: "Remove source files after successful backup"
    option :all, type: :boolean, default: false, desc: "Backup all repositories (multi-repo config only)"
    def backup
      @logger.info("Starting backup operation with config: #{options[:config]}")
      config = Config.new(options[:config])

      if config.multi_repo?
        backup_multi_repo(config)
      else
        backup_single_repo(config)
      end
    rescue Error => e
      @logger.error("Backup failed: #{e.message}")
      error_exit(e)
    end

    desc "list", "List all archives in the repository"
    def list
      @logger.info("Listing archives in repository")
      config = Config.new(options[:config])
      passphrase = fetch_passphrase_from_config(config)

      repo = Repository.new(config.repository, passphrase: passphrase)

      # Auto-initialize repository if configured
      if config.auto_init? && !repo.exists?
        @logger.info("Auto-initializing repository at #{config.repository}")
        repo.create
        puts "Repository auto-initialized at #{config.repository}"
      end

      repo.list
      @logger.info("Successfully listed archives")
    rescue Error => e
      @logger.error("Failed to list archives: #{e.message}")
      error_exit(e)
    end

    desc "restore ARCHIVE", "Restore files from an archive"
    option :destination, type: :string, default: ".", desc: "Destination directory"
    option :path, type: :string, desc: "Specific file or directory path to restore from archive"
    def restore(archive_name)
      restore_target = options[:path] ? "#{options[:path]} from #{archive_name}" : archive_name
      @logger.info("Restoring #{restore_target} to #{options[:destination]}")
      config = Config.new(options[:config])
      passphrase = fetch_passphrase_from_config(config)

      repo = Repository.new(config.repository, passphrase: passphrase)
      backup = Backup.new(repo, config: config)

      backup.extract(archive_name, destination: options[:destination], path: options[:path])
      @logger.info("Successfully restored #{restore_target} to #{options[:destination]}")

      if options[:path]
        puts "Restored #{options[:path]} from #{archive_name} to #{options[:destination]}"
      else
        puts "Archive restored to #{options[:destination]}"
      end
    rescue Error => e
      @logger.error("Failed to restore archive: #{e.message}")
      error_exit(e)
    end

    desc "info", "Show repository information"
    def info
      @logger.info("Retrieving repository information")
      config = Config.new(options[:config])
      passphrase = fetch_passphrase_from_config(config)

      repo = Repository.new(config.repository, passphrase: passphrase)

      # Auto-initialize repository if configured
      if config.auto_init? && !repo.exists?
        @logger.info("Auto-initializing repository at #{config.repository}")
        repo.create
        puts "Repository auto-initialized at #{config.repository}"
      end

      repo.info
      @logger.info("Successfully retrieved repository information")
    rescue Error => e
      @logger.error("Failed to get repository info: #{e.message}")
      error_exit(e)
    end

    private

    def get_passphrase(passphrase, passbolt_id)
      return passphrase if passphrase
      return Passbolt.new(resource_id: passbolt_id).get_password if passbolt_id

      nil
    end

    def fetch_passphrase_from_config(config)
      passbolt_config = config.passbolt_integration
      return nil if passbolt_config.empty?

      Passbolt.new(resource_id: passbolt_config["resource_id"]).get_password
    end

    def error_exit(error)
      puts "Error: #{error.message}"
      exit 1
    end

    # Single repository backup (legacy)
    def backup_single_repo(config)
      @logger.info("Backing up paths: #{config.backup_paths.join(', ')}")
      passphrase = fetch_passphrase_from_config(config)

      repo = Repository.new(config.repository, passphrase: passphrase)

      # Auto-initialize repository if configured
      if config.auto_init? && !repo.exists?
        @logger.info("Auto-initializing repository at #{config.repository}")
        repo.create
        puts "Repository auto-initialized at #{config.repository}"
      end

      backup = Backup.new(repo, config: config)

      archive_name = options[:name] || Time.now.strftime("%Y-%m-%d_%H-%M-%S")
      @logger.info("Creating archive: #{archive_name}")
      backup.create(name: options[:name], remove_source: options[:remove_source])
      @logger.info("Backup created successfully: #{archive_name}")

      if options[:remove_source]
        @logger.info("Removed source files: #{config.backup_paths.join(', ')}")
      end

      puts "Backup created successfully"
      puts "Source files removed" if options[:remove_source]
    end

    # Multi-repository backup
    def backup_multi_repo(config)
      global_settings = config.global_settings
      repos_to_backup = if options[:all]
                          config.repositories
                        elsif options[:repository]
                          repo_config = config.get_repository(options[:repository])
                          raise ConfigError, "Repository '#{options[:repository]}' not found" unless repo_config
                          [repo_config]
                        else
                          raise ConfigError, "Please specify --repository or --all for multi-repo config"
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

      passphrase = fetch_passphrase_for_repo(merged_config)
      repo = Repository.new(repo_config["path"], passphrase: passphrase)

      # Auto-initialize if configured
      auto_init = merged_config["auto_init"] || false
      if auto_init && !repo.exists?
        @logger.info("Auto-initializing repository at #{repo_config['path']}")
        repo.create
        puts "Repository auto-initialized at #{repo_config['path']}"
      end

      # Create backup config wrapper
      backup_config = BackupConfig.new(repo_config, merged_config)
      backup = Backup.new(repo, config: backup_config)

      archive_name = options[:name] || "#{repo_name}-#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}"
      @logger.info("Creating archive: #{archive_name}")

      sources = repo_config["sources"] || []
      @logger.info("Backing up #{sources.size} source(s)")

      backup.create(name: archive_name, remove_source: options[:remove_source])
      @logger.info("Backup created successfully: #{archive_name}")

      puts "✓ Backup created: #{archive_name}"
      puts "  Sources removed" if options[:remove_source]
    end

    def fetch_passphrase_for_repo(repo_config)
      passbolt_config = repo_config["passbolt"]
      return nil if passbolt_config.nil? || passbolt_config.empty?

      Passbolt.new(resource_id: passbolt_config["resource_id"]).get_password
    end

    # Wrapper class to adapt multi-repo config to existing Backup class
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
          patterns += (source["exclude"] || [])
        end
        patterns += (@merged_settings["exclude_patterns"] || [])
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