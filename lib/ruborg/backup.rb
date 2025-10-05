# frozen_string_literal: true

module Ruborg
  # Backup operations using Borg
  class Backup
    def initialize(repository, config:)
      @repository = repository
      @config = config
    end

    def create(name: nil, remove_source: false)
      raise BorgError, "Repository does not exist" unless @repository.exists?

      archive_name = name || Time.now.strftime("%Y-%m-%d_%H-%M-%S")
      cmd = build_create_command(archive_name)

      execute_borg_command(cmd)

      remove_source_files if remove_source
    end

    def extract(archive_name, destination: ".", path: nil)
      raise BorgError, "Repository does not exist" unless @repository.exists?

      cmd = ["borg", "extract", "#{@repository.path}::#{archive_name}"]
      cmd << path if path

      # Change to destination directory if specified
      if destination != "."
        require "fileutils"
        FileUtils.mkdir_p(destination) unless File.directory?(destination)
        Dir.chdir(destination) do
          execute_borg_command(cmd)
        end
      else
        execute_borg_command(cmd)
      end
    end

    def list_archives
      @repository.list
    end

    def delete(archive_name)
      cmd = ["borg", "delete", "#{@repository.path}::#{archive_name}"]
      execute_borg_command(cmd)
    end

    private

    def build_create_command(archive_name)
      cmd = ["borg", "create"]
      cmd += ["--compression", @config.compression]

      @config.exclude_patterns.each do |pattern|
        cmd += ["--exclude", pattern]
      end

      cmd << "#{@repository.path}::#{archive_name}"
      cmd += @config.backup_paths

      cmd
    end

    def execute_borg_command(cmd)
      env = {}
      passphrase = @repository.instance_variable_get(:@passphrase)
      env["BORG_PASSPHRASE"] = passphrase if passphrase
      env["BORG_RELOCATED_REPO_ACCESS_IS_OK"] = "yes"
      env["BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK"] = "yes"

      result = system(env, *cmd, in: "/dev/null")
      raise BorgError, "Borg command failed: #{cmd.join(' ')}" unless result

      result
    end

    def remove_source_files
      require "fileutils"

      @config.backup_paths.each do |path|
        if File.directory?(path)
          FileUtils.rm_rf(path)
        elsif File.file?(path)
          FileUtils.rm(path)
        end
      end
    end
  end
end