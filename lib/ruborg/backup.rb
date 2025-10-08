# frozen_string_literal: true

module Ruborg
  # Backup operations using Borg
  class Backup
    def initialize(repository, config:, retention_mode: "standard", repo_name: nil, logger: nil)
      @repository = repository
      @config = config
      @retention_mode = retention_mode
      @repo_name = repo_name
      @logger = logger
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

      # Show repository header in console only
      print_repository_header

      # Show progress in console
      puts "Creating archive: #{archive_name}"

      cmd = build_create_command(archive_name)

      execute_borg_command(cmd)

      # Log successful action
      @logger&.info("[#{@repo_name}] Created archive #{archive_name} with #{@config.backup_paths.size} source(s)")
      puts "✓ Archive created successfully"

      remove_source_files if remove_source
    end

    def create_per_file_archives(name_prefix, remove_source)
      # Collect all files from backup paths
      files_to_backup = collect_files_from_paths(@config.backup_paths, @config.exclude_patterns)

      raise BorgError, "No files found to backup" if files_to_backup.empty?

      # Show repository header in console only
      print_repository_header

      puts "Found #{files_to_backup.size} file(s) to backup"

      files_to_backup.each_with_index do |file_path, index|
        # Generate hash-based archive name with filename
        path_hash = generate_path_hash(file_path)
        filename = File.basename(file_path)
        sanitized_filename = sanitize_filename(filename)

        # Use file modification time for timestamp (not backup creation time)
        file_mtime = File.mtime(file_path).strftime("%Y-%m-%d_%H-%M-%S")

        # Ensure archive name doesn't exceed 255 characters (filesystem limit)
        archive_name = name_prefix || build_archive_name(@repo_name, sanitized_filename, path_hash, file_mtime)

        # Show progress in console
        puts "  [#{index + 1}/#{files_to_backup.size}] Backing up: #{file_path}"

        # Create archive for single file with original path as comment
        cmd = build_per_file_create_command(archive_name, file_path)

        execute_borg_command(cmd)

        # Log successful action with details
        @logger&.info("[#{@repo_name}] Archived #{file_path} in archive #{archive_name}")
      end

      puts "✓ Per-file backup completed: #{files_to_backup.size} file(s) backed up"

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

    def sanitize_filename(filename)
      # Remove or replace characters that are not safe for archive names
      # Allow alphanumeric, dash, underscore, and dot
      sanitized = filename.gsub(/[^a-zA-Z0-9._-]/, "_")

      # Ensure the sanitized name is not empty
      sanitized = "file" if sanitized.empty? || sanitized.strip.empty?

      sanitized
    end

    def build_archive_name(repo_name, sanitized_filename, path_hash, timestamp)
      # Maximum filename length for most filesystems (ext4, NTFS, APFS)
      max_length = 255

      # Calculate fixed portions: separators (3) + hash (12) + timestamp (19)
      fixed_length = 3 + path_hash.length + timestamp.length
      repo_name_length = repo_name ? repo_name.length : 0

      # Calculate available space for filename
      available_for_filename = max_length - fixed_length - repo_name_length

      # Truncate filename if necessary, preserving file extension if possible
      truncated_filename = if sanitized_filename.length > available_for_filename
                             truncate_with_extension(sanitized_filename, available_for_filename)
                           else
                             sanitized_filename
                           end

      "#{repo_name}-#{truncated_filename}-#{path_hash}-#{timestamp}"
    end

    def truncate_with_extension(filename, max_length)
      return "" if max_length <= 0
      return filename if filename.length <= max_length

      # Try to preserve extension (last .xxx)
      if filename.include?(".") && filename !~ /^\./
        parts = filename.rpartition(".")
        basename = parts[0]
        extension = parts[2]

        # Reserve space for extension plus dot
        extension_length = extension.length + 1

        if extension_length < max_length
          basename_max = max_length - extension_length
          "#{basename[0...basename_max]}.#{extension}"
        else
          # Extension too long, just truncate entire filename
          filename[0...max_length]
        end
      else
        # No extension, just truncate
        filename[0...max_length]
      end
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

      extract_target = path ? "#{path} from #{archive_name}" : archive_name
      @logger&.info("Extracting #{extract_target} to #{destination}")

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

      @logger&.info("Extraction completed successfully")
    end

    def list_archives
      @repository.list
    end

    def delete(archive_name)
      @logger&.info("Deleting archive: #{archive_name}")
      cmd = [@repository.borg_path, "delete", "#{@repository.path}::#{archive_name}"]
      execute_borg_command(cmd)
      @logger&.info("Archive deleted successfully: #{archive_name}")
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

      @logger&.info("Removing source files after successful backup")

      removed_count = 0

      @config.backup_paths.each do |path|
        # Resolve symlinks and validate path
        begin
          real_path = File.realpath(path)
        rescue Errno::ENOENT
          # Path doesn't exist, skip
          @logger&.warn("Source path does not exist, skipping: #{path}")
          next
        end

        # Security check: ensure path hasn't been tampered with
        unless File.exist?(real_path)
          @logger&.warn("Source path no longer exists, skipping: #{real_path}")
          next
        end

        # Additional safety: don't delete root or system directories
        if real_path == "/" || real_path.start_with?("/bin", "/sbin", "/usr", "/etc", "/sys", "/proc")
          @logger&.error("Refusing to delete system path: #{real_path}")
          raise BorgError, "Refusing to delete system path: #{real_path}"
        end

        file_type = File.directory?(real_path) ? "directory" : "file"
        @logger&.info("Removing #{file_type}: #{real_path}")

        if File.directory?(real_path)
          FileUtils.rm_rf(real_path, secure: true)
        elsif File.file?(real_path)
          FileUtils.rm(real_path)
        end

        removed_count += 1
      end

      @logger&.info("Source file removal completed: #{removed_count} item(s) removed")
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

    def print_repository_header
      puts "\n" + ("=" * 60)
      puts "  Repository: #{@repo_name}"
      puts "=" * 60
    end
  end
end
