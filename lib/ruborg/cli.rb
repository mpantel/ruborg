# frozen_string_literal: true

require "thor"

module Ruborg
  # Command-line interface for ruborg
  class CLI < Thor
    class_option :config, type: :string, default: "ruborg.yml", desc: "Path to configuration file"
    class_option :log, type: :string, desc: "Path to log file"

    def initialize(*args)
      super
      @logger = RuborgLogger.new(log_file: options[:log])
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
    def backup
      @logger.info("Starting backup operation with config: #{options[:config]}")
      config = Config.new(options[:config])
      @logger.info("Backing up paths: #{config.backup_paths.join(', ')}")
      passphrase = fetch_passphrase_from_config(config)

      repo = Repository.new(config.repository, passphrase: passphrase)
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
  end
end