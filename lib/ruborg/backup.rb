# frozen_string_literal: true

module Ruborg
  # Backup operations using Borg
  class Backup
    def initialize(repository, config:, retention_mode: "standard", repo_name: nil)
      @repository = repository
      @config = config
      @retention_mode = retention_mode
      @repo_name = repo_name
    end

    def create(name: nil, remove_source: false)
      raise BorgError, "Repository does not exist" unless @repository.exists?

      if @retention_mode == "per_file"
        create_per_file_archives(name, remove_source)
      else
        create_standard_archive(name, remove_source)
      end
    end

    private

    def create_standard_archive(name, remove_source)
      archive_name = name || Time.now.strftime("%Y-%m-%d_%H-%M-%S")
      cmd = build_create_command(archive_name)

      execute_borg_command(cmd)

      remove_source_files if remove_source
    end

    def create_per_file_archives(name_prefix, remove_source)
      # Collect all files from backup paths
      files_to_backup = collect_files_from_paths(@config.backup_paths, @config.exclude_patterns)

      raise BorgError, "No files found to backup" if files_to_backup.empty?

      timestamp = Time.now.strftime("%Y-%m-%d_%H-%M-%S")

      files_to_backup.each do |file_path|
        # Generate hash-based archive name
        path_hash = generate_path_hash(file_path)
        archive_name = name_prefix || "#{@repo_name}-#{path_hash}-#{timestamp}"

        # Create archive for single file with original path as comment
        cmd = build_per_file_create_command(archive_name, file_path)

        execute_borg_command(cmd)
      end

      # NOTE: remove_source handled per file after successful backup
      remove_source_files if remove_source
    end

    def collect_files_from_paths(paths, exclude_patterns)
      require "find"
      files = []

      paths.each do |base_path|
        base_path = File.expand_path(base_path)

        if File.file?(base_path)
          files << base_path unless excluded?(base_path, exclude_patterns)
        elsif File.directory?(base_path)
          Find.find(base_path) do |path|
            next unless File.file?(path)
            next if excluded?(path, exclude_patterns)

            files << path
          end
        end
      end

      files
    end

    def excluded?(path, patterns)
      patterns.any? do |pattern|
        # Try matching against full path and just the filename
        File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_DOTMATCH) ||
          File.fnmatch?(pattern, File.basename(path), File::FNM_DOTMATCH)
      end
    end

    def generate_path_hash(file_path)
      require "digest"
      # Use SHA256 and take first 12 characters for uniqueness
      Digest::SHA256.hexdigest(file_path)[0...12]
    end

    def build_per_file_create_command(archive_name, file_path)
      cmd = [@repository.borg_path, "create"]
      cmd += ["--compression", @config.compression]

      # Store original path in archive comment for retrieval
      cmd += ["--comment", file_path]

      cmd << "#{@repository.path}::#{archive_name}"
      cmd << file_path

      cmd
    end

    public

    def extract(archive_name, destination: ".", path: nil)
      raise BorgError, "Repository does not exist" unless @repository.exists?

      cmd = [@repository.borg_path, "extract", "#{@repository.path}::#{archive_name}"]
      cmd << path if path

      # Change to destination directory if specified
      if destination == "."
        execute_borg_command(cmd)
      else
        require "fileutils"

        # Validate and normalize destination path
        validated_dest = validate_destination_path(destination)
        FileUtils.mkdir_p(validated_dest) unless File.directory?(validated_dest)

        Dir.chdir(validated_dest) do
          execute_borg_command(cmd)
        end
      end
    end

    def list_archives
      @repository.list
    end

    def delete(archive_name)
      cmd = [@repository.borg_path, "delete", "#{@repository.path}::#{archive_name}"]
      execute_borg_command(cmd)
    end

    private

    def build_create_command(archive_name)
      cmd = [@repository.borg_path, "create"]
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
      raise BorgError, "Borg command failed: #{cmd.join(" ")}" unless result

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
        next unless File.exist?(real_path)

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
