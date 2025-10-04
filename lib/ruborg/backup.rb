# frozen_string_literal: true

module Ruborg
  # Backup operations using Borg
  class Backup
    def initialize(repository, config:)
      @repository = repository
      @config = config
    end

    def create(name: nil)
      raise BorgError, "Repository does not exist" unless @repository.exists?

      archive_name = name || Time.now.strftime("%Y-%m-%d_%H-%M-%S")
      cmd = build_create_command(archive_name)

      execute_borg_command(cmd)
    end

    def extract(archive_name, destination: ".")
      raise BorgError, "Repository does not exist" unless @repository.exists?

      cmd = ["borg", "extract", "#{@repository.path}::#{archive_name}"]
      cmd += ["--destination", destination] if destination != "."

      execute_borg_command(cmd)
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
      result = system(*cmd)
      raise BorgError, "Borg command failed: #{cmd.join(' ')}" unless result

      result
    end
  end
end