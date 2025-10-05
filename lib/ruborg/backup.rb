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

        # Validate and normalize destination path
        validated_dest = validate_destination_path(destination)
        FileUtils.mkdir_p(validated_dest) unless File.directory?(validated_dest)

        Dir.chdir(validated_dest) do
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

      # Validate and normalize backup paths
      validated_paths = validate_backup_paths(@config.backup_paths)
      cmd += validated_paths

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
        # Resolve symlinks and validate path
        begin
          real_path = File.realpath(path)
        rescue Errno::ENOENT
          # Path doesn't exist, skip
          next
        end

        # Security check: ensure path hasn't been tampered with
        unless File.exist?(real_path)
          next
        end

        # Additional safety: don't delete root or system directories
        if real_path == "/" || real_path.start_with?("/bin", "/sbin", "/usr", "/etc", "/sys", "/proc")
          raise BorgError, "Refusing to delete system path: #{real_path}"
        end

        if File.directory?(real_path)
          FileUtils.rm_rf(real_path, secure: true)
        elsif File.file?(real_path)
          FileUtils.rm(real_path)
        end
      end
    end

    def validate_destination_path(destination)
      # Expand and normalize the path
      normalized_path = File.expand_path(destination)

      # Security check: prevent path traversal to sensitive directories
      forbidden_paths = ["/", "/bin", "/sbin", "/usr", "/etc", "/sys", "/proc", "/boot"]
      forbidden_paths.each do |forbidden|
        if normalized_path == forbidden || normalized_path.start_with?("#{forbidden}/")
          raise BorgError, "Invalid destination: refusing to extract to system directory #{normalized_path}"
        end
      end

      normalized_path
    end

    def validate_backup_paths(paths)
      raise BorgError, "No backup paths specified" if paths.nil? || paths.empty?

      paths.map do |path|
        raise BorgError, "Empty backup path specified" if path.nil? || path.to_s.strip.empty?
        File.expand_path(path)
      end
    end
  end
end