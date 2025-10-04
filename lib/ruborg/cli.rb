# frozen_string_literal: true

require "thor"

module Ruborg
  # Command-line interface for ruborg
  class CLI < Thor
    class_option :config, type: :string, default: "ruborg.yml", desc: "Path to configuration file"

    desc "init REPOSITORY", "Initialize a new Borg repository"
    option :passphrase, type: :string, desc: "Repository passphrase"
    option :passbolt_id, type: :string, desc: "Passbolt resource ID for passphrase"
    def init(repository_path)
      passphrase = get_passphrase(options[:passphrase], options[:passbolt_id])
      repo = Repository.new(repository_path, passphrase: passphrase)
      repo.create
      puts "Repository initialized at #{repository_path}"
    rescue Error => e
      error_exit(e)
    end

    desc "backup", "Create a backup using configuration file"
    option :name, type: :string, desc: "Archive name"
    def backup
      config = Config.new(options[:config])
      passphrase = fetch_passphrase_from_config(config)

      repo = Repository.new(config.repository, passphrase: passphrase)
      backup = Backup.new(repo, config: config)

      backup.create(name: options[:name])
      puts "Backup created successfully"
    rescue Error => e
      error_exit(e)
    end

    desc "list", "List all archives in the repository"
    def list
      config = Config.new(options[:config])
      passphrase = fetch_passphrase_from_config(config)

      repo = Repository.new(config.repository, passphrase: passphrase)
      repo.list
    rescue Error => e
      error_exit(e)
    end

    desc "restore ARCHIVE", "Restore files from an archive"
    option :destination, type: :string, default: ".", desc: "Destination directory"
    def restore(archive_name)
      config = Config.new(options[:config])
      passphrase = fetch_passphrase_from_config(config)

      repo = Repository.new(config.repository, passphrase: passphrase)
      backup = Backup.new(repo, config: config)

      backup.extract(archive_name, destination: options[:destination])
      puts "Archive restored to #{options[:destination]}"
    rescue Error => e
      error_exit(e)
    end

    desc "info", "Show repository information"
    def info
      config = Config.new(options[:config])
      passphrase = fetch_passphrase_from_config(config)

      repo = Repository.new(config.repository, passphrase: passphrase)
      repo.info
    rescue Error => e
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