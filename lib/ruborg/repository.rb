# frozen_string_literal: true

require "English"
module Ruborg
  # Borg repository management
  class Repository
    attr_reader :path, :borg_path

    def initialize(path, passphrase: nil, borg_options: {}, borg_path: nil, logger: nil)
      @path = validate_repo_path(path)
      @passphrase = passphrase
      @borg_options = borg_options
      @borg_path = validate_borg_path(borg_path || "borg")
      @logger = logger
    end

    def exists?
      File.directory?(@path) && File.exist?(File.join(@path, "config"))
    end

    def create
      raise BorgError, "Repository already exists at #{@path}" if exists?

      @logger&.info("Creating Borg repository at #{@path} with repokey encryption")
      cmd = [@borg_path, "init", "--encryption=repokey", @path]
      execute_borg_command(cmd)
      @logger&.info("Repository created successfully at #{@path}")
    end

    def info
      raise BorgError, "Repository does not exist at #{@path}" unless exists?

      cmd = [@borg_path, "info", @path]
      execute_borg_command(cmd)
    end

    def list
      raise BorgError, "Repository does not exist at #{@path}" unless exists?

      cmd = [@borg_path, "list", @path]
      execute_borg_command(cmd)
    end

    def list_archive(archive_name)
      raise BorgError, "Repository does not exist at #{@path}" unless exists?
      raise BorgError, "Archive name cannot be empty" if archive_name.nil? || archive_name.strip.empty?

      cmd = [@borg_path, "list", "#{@path}::#{archive_name}"]
      execute_borg_command(cmd)
    end

    def get_archive_info(archive_name)
      raise BorgError, "Repository does not exist at #{@path}" unless exists?
      raise BorgError, "Archive name cannot be empty" if archive_name.nil? || archive_name.strip.empty?

      require "json"
      require "open3"

      cmd = [@borg_path, "info", "#{@path}::#{archive_name}", "--json"]
      env = build_borg_env

      stdout, stderr, status = Open3.capture3(env, *cmd)
      raise BorgError, "Failed to get archive info: #{stderr}" unless status.success?

      JSON.parse(stdout)
    rescue JSON::ParserError => e
      raise BorgError, "Failed to parse archive info: #{e.message}"
    end

    def get_file_metadata(archive_name, file_path: nil)
      raise BorgError, "Repository does not exist at #{@path}" unless exists?
      raise BorgError, "Archive name cannot be empty" if archive_name.nil? || archive_name.strip.empty?

      require "json"
      require "open3"

      # Get archive info to check if it's a per-file archive
      archive_info = get_archive_info(archive_name)
      comment = archive_info.dig("archives", 0, "comment")

      # If it's a per-file archive (has comment with original path), get metadata for that file
      # Otherwise, require file_path parameter
      if comment && !comment.empty?
        # Per-file archive - get metadata for the single file
        get_file_metadata_from_archive(archive_name, nil)
      else
        # Standard archive - require file_path
        raise BorgError, "file_path parameter required for standard archives" if file_path.nil? || file_path.empty?

        get_file_metadata_from_archive(archive_name, file_path)
      end
    end

    private

    def get_file_metadata_from_archive(archive_name, file_path)
      require "json"
      require "open3"

      cmd = [@borg_path, "list", "#{@path}::#{archive_name}", "--json-lines"]
      env = build_borg_env

      stdout, stderr, status = Open3.capture3(env, *cmd)
      raise BorgError, "Failed to list archive contents: #{stderr}" unless status.success?

      # Parse JSON lines
      files = stdout.lines.map do |line|
        JSON.parse(line)
      end

      # If file_path specified, find that specific file
      if file_path
        # Borg stores absolute paths by stripping the leading slash
        # For example: /var/folders/foo -> var/folders/foo
        # Try both the original path and the path with leading slash removed
        normalized_path = file_path.start_with?("/") ? file_path[1..] : file_path
        file_metadata = files.find { |f| [file_path, normalized_path].include?(f["path"]) }
        raise BorgError, "File '#{file_path}' not found in archive" unless file_metadata

        file_metadata
      else
        # Per-file archive - return metadata for the single file (first file)
        raise BorgError, "Archive appears to be empty" if files.empty?

        files.first
      end
    rescue JSON::ParserError => e
      raise BorgError, "Failed to parse file metadata: #{e.message}"
    end

    public

    def prune(retention_policy = {}, retention_mode: "standard")
      raise BorgError, "Repository does not exist at #{@path}" unless exists?
      raise BorgError, "No retention policy specified" if retention_policy.nil? || retention_policy.empty?

      if retention_mode == "per_file"
        prune_per_file_archives(retention_policy)
      else
        prune_standard_archives(retention_policy)
      end
    end

    private

    def prune_standard_archives(retention_policy)
      cmd = [@borg_path, "prune", @path, "--stats"]

      # Add count-based retention options
      cmd += ["--keep-hourly", retention_policy["keep_hourly"].to_s] if retention_policy["keep_hourly"]
      cmd += ["--keep-daily", retention_policy["keep_daily"].to_s] if retention_policy["keep_daily"]
      cmd += ["--keep-weekly", retention_policy["keep_weekly"].to_s] if retention_policy["keep_weekly"]
      cmd += ["--keep-monthly", retention_policy["keep_monthly"].to_s] if retention_policy["keep_monthly"]
      cmd += ["--keep-yearly", retention_policy["keep_yearly"].to_s] if retention_policy["keep_yearly"]

      # Add time-based retention options
      cmd += ["--keep-within", retention_policy["keep_within"]] if retention_policy["keep_within"]
      cmd += ["--keep-last", retention_policy["keep_last"]] if retention_policy["keep_last"]

      execute_borg_command(cmd)
    end

    def prune_per_file_archives(retention_policy)
      # Get file metadata-based retention setting
      keep_files_modified_within = retention_policy["keep_files_modified_within"]

      unless keep_files_modified_within
        # Fall back to standard pruning if no file metadata retention specified
        @logger&.info("No file metadata retention specified, using standard pruning per directory")
        prune_per_directory_standard(retention_policy)
        return
      end

      @logger&.info("Pruning per-file archives based on file modification time (keep within: #{keep_files_modified_within})")

      # Parse time duration (e.g., "30d" -> 30 days)
      cutoff_time = Time.now - parse_time_duration(keep_files_modified_within)

      # Get all archives with metadata including source directory
      archives_by_source = get_archives_grouped_by_source_dir
      @logger&.info("Found #{archives_by_source.values.sum(&:size)} archive(s) in #{archives_by_source.size} source director(ies)")

      total_deleted = 0

      # Process each source directory separately
      archives_by_source.each do |source_dir, archives|
        source_desc = source_dir.empty? ? "legacy archives (no source dir)" : source_dir
        @logger&.info("Processing source directory: #{source_desc} (#{archives.size} archives)")

        archives_to_delete = []

        archives.each do |archive|
          # Get file metadata from archive
          file_mtime = get_file_mtime_from_archive(archive[:name])

          # Delete archive if file was modified before cutoff
          if file_mtime && file_mtime < cutoff_time
            archives_to_delete << archive[:name]
            @logger&.debug("Archive #{archive[:name]} marked for deletion (file mtime: #{file_mtime})")
          end
        end

        next if archives_to_delete.empty?

        @logger&.info("Deleting #{archives_to_delete.size} archive(s) from #{source_desc}")

        # Delete archives
        archives_to_delete.each do |archive_name|
          @logger&.debug("Deleting archive: #{archive_name}")
          delete_archive(archive_name)
        end

        total_deleted += archives_to_delete.size
      end

      if total_deleted.zero?
        @logger&.info("No archives to prune")
        puts "No archives to prune"
      else
        @logger&.info("Pruned #{total_deleted} archive(s) total across all source directories")
        puts "Pruned #{total_deleted} archive(s) based on file modification time"
      end
    end

    def list_archives_with_metadata
      require "json"
      require "time"
      require "open3"

      cmd = [@borg_path, "list", @path, "--json"]
      env = build_borg_env

      # Use Open3.capture3 for safe command execution with environment variables
      stdout, stderr, status = Open3.capture3(env, *cmd)

      raise BorgError, "Failed to list archives: #{stderr}" unless status.success?

      json_data = JSON.parse(stdout)
      archives = json_data["archives"] || []

      archives.map do |archive|
        {
          name: archive["name"],
          time: Time.parse(archive["time"])
        }
      end
    rescue JSON::ParserError => e
      raise BorgError, "Failed to parse archive list: #{e.message}"
    end

    def get_file_mtime_from_archive(archive_name)
      require "json"
      require "time"
      require "open3"

      cmd = [@borg_path, "list", "#{@path}::#{archive_name}", "--json-lines"]
      env = build_borg_env

      # Use Open3.capture3 for safe command execution with environment variables
      stdout, _stderr, status = Open3.capture3(env, *cmd)

      unless status.success?
        return nil # Archive might be corrupted or inaccessible
      end

      # Parse first line (should be the only file in per-file archives)
      first_line = stdout.lines.first
      return nil unless first_line

      file_data = JSON.parse(first_line)
      mtime_str = file_data["mtime"]

      return nil unless mtime_str

      # Parse mtime (format: "2025-10-06T12:34:56.123456")
      Time.parse(mtime_str)
    rescue JSON::ParserError, ArgumentError
      nil # Failed to parse, skip this archive
    end

    def get_archives_grouped_by_source_dir
      require "json"
      require "time"
      require "open3"

      # Get list of all archives
      cmd = [@borg_path, "list", @path, "--json"]
      env = build_borg_env

      stdout, stderr, status = Open3.capture3(env, *cmd)
      raise BorgError, "Failed to list archives: #{stderr}" unless status.success?

      json_data = JSON.parse(stdout)
      archives = json_data["archives"] || []

      # Group archives by source directory from metadata
      archives_by_source = Hash.new { |h, k| h[k] = [] }

      archives.each do |archive|
        archive_name = archive["name"]

        # Get archive info to read comment (metadata)
        info_cmd = [@borg_path, "info", "#{@path}::#{archive_name}", "--json"]
        info_stdout, _, info_status = Open3.capture3(env, *info_cmd)

        unless info_status.success?
          # If we can't get info, put in legacy group
          archives_by_source[""] << {
            name: archive_name,
            time: Time.parse(archive["time"])
          }
          next
        end

        info_data = JSON.parse(info_stdout)
        comment = info_data.dig("archives", 0, "comment") || ""

        # Parse source_dir from comment
        # Format: path|||size|||hash|||source_dir
        source_dir = if comment.include?("|||")
                       parts = comment.split("|||")
                       parts.length >= 4 ? (parts[3] || "") : ""
                     else
                       ""
                     end

        archives_by_source[source_dir] << {
          name: archive_name,
          time: Time.parse(archive["time"])
        }
      end

      archives_by_source
    rescue JSON::ParserError => e
      raise BorgError, "Failed to parse archive metadata: #{e.message}"
    end

    def prune_per_directory_standard(retention_policy)
      # Apply standard retention policies (keep_daily, etc.) per source directory
      archives_by_source = get_archives_grouped_by_source_dir
      @logger&.info("Applying standard retention per directory: #{archives_by_source.size} director(ies)")

      total_pruned = 0

      archives_by_source.each do |source_dir, archives|
        source_desc = source_dir.empty? ? "legacy archives (no source dir)" : source_dir
        @logger&.info("Processing source directory: #{source_desc} (#{archives.size} archives)")

        # Create a temporary prefix to filter this directory's archives
        # Since we can't directly use borg prune with filtering, we need to delete individually
        archives_to_keep = apply_retention_policy(archives, retention_policy)
        archives_to_delete = archives.map { |a| a[:name] } - archives_to_keep.map { |a| a[:name] }

        next if archives_to_delete.empty?

        @logger&.info("Pruning #{archives_to_delete.size} archive(s) from #{source_desc}")

        archives_to_delete.each do |archive_name|
          @logger&.debug("Deleting archive: #{archive_name}")
          delete_archive(archive_name)
        end

        total_pruned += archives_to_delete.size
      end

      if total_pruned.zero?
        @logger&.info("No archives to prune")
        puts "No archives to prune"
      else
        @logger&.info("Pruned #{total_pruned} archive(s) total across all source directories")
        puts "Pruned #{total_pruned} archive(s) across all source directories"
      end
    end

    def apply_retention_policy(archives, policy)
      # Sort archives by time (newest first)
      sorted = archives.sort_by { |a| a[:time] }.reverse
      to_keep = []

      # Apply keep_last first (if specified)
      to_keep += sorted.take(policy["keep_last"]) if policy["keep_last"]

      # Apply time-based retention (keep_within)
      if policy["keep_within"]
        cutoff = Time.now - parse_time_duration(policy["keep_within"])
        to_keep += sorted.select { |a| a[:time] >= cutoff }
      end

      # Apply count-based retention (keep_daily, keep_weekly, etc.)
      # Group archives by time period and keep the newest from each period
      %w[hourly daily weekly monthly yearly].each do |period|
        keep_count = policy["keep_#{period}"]
        next unless keep_count

        case period
        when "hourly"
          grouped = sorted.group_by { |a| a[:time].strftime("%Y-%m-%d-%H") }
        when "daily"
          grouped = sorted.group_by { |a| a[:time].strftime("%Y-%m-%d") }
        when "weekly"
          grouped = sorted.group_by { |a| a[:time].strftime("%Y-W%W") }
        when "monthly"
          grouped = sorted.group_by { |a| a[:time].strftime("%Y-%m") }
        when "yearly"
          grouped = sorted.group_by { |a| a[:time].strftime("%Y") }
        end

        # Keep the newest archive from each of the most recent N periods
        grouped.keys.sort.reverse.take(keep_count.to_i).each do |key|
          to_keep << grouped[key].first
        end
      end

      to_keep.uniq { |a| a[:name] }
    end

    def delete_archive(archive_name)
      cmd = [@borg_path, "delete", "#{@path}::#{archive_name}"]
      execute_borg_command(cmd)
    end

    def parse_time_duration(duration_str)
      # Parse duration strings like "30d", "7w", "6m", "1y"
      match = duration_str.match(/^(\d+)([dwmy])$/)
      raise BorgError, "Invalid time duration format: #{duration_str}" unless match

      value = match[1].to_i
      unit = match[2]

      case unit
      when "d"
        value * 24 * 60 * 60 # days to seconds
      when "w"
        value * 7 * 24 * 60 * 60 # weeks to seconds
      when "m"
        value * 30 * 24 * 60 * 60 # months (approx) to seconds
      when "y"
        value * 365 * 24 * 60 * 60 # years (approx) to seconds
      end
    end

    def build_borg_env
      env = {}
      env["BORG_PASSPHRASE"] = @passphrase if @passphrase

      # Use strict boolean checking (only true/false allowed, default to true for backward compatibility)
      allow_relocated = @borg_options.fetch("allow_relocated_repo", true)
      allow_relocated = true unless allow_relocated == false # Normalize: only false disables, everything else enables

      allow_unencrypted = @borg_options.fetch("allow_unencrypted_repo", true)
      allow_unencrypted = true unless allow_unencrypted == false # Normalize: only false disables, everything else enables

      env["BORG_RELOCATED_REPO_ACCESS_IS_OK"] = allow_relocated ? "yes" : "no"
      env["BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK"] = allow_unencrypted ? "yes" : "no"

      env
    end

    public

    def check
      raise BorgError, "Repository does not exist at #{@path}" unless exists?

      cmd = [@borg_path, "check", @path]
      execute_borg_command(cmd)
    end

    # Get Borg version
    def self.borg_version(borg_path = "borg")
      output, status = execute_version_command(borg_path)
      raise BorgError, "Borg is not installed or not in PATH" unless status.success?

      # Parse version from output like "borg 1.2.8"
      match = output.match(/borg (\d+\.\d+\.\d+)/)
      raise BorgError, "Could not parse Borg version from: #{output}" unless match

      match[1]
    end

    # Get Borg path (full path to executable)
    def self.borg_path(borg_command = "borg")
      # If it's an absolute or relative path, expand it
      return File.expand_path(borg_command) if borg_command.include?("/")

      # Otherwise, search in PATH
      ENV["PATH"].split(File::PATH_SEPARATOR).each do |directory|
        path = File.join(directory, borg_command)
        return path if File.executable?(path)
      end

      # Not found in PATH, return the command as-is
      borg_command
    end

    # Execute borg version command (extracted for testing)
    def self.execute_version_command(borg_path = "borg")
      require "open3"

      # Use Open3.capture2e for safe command execution
      output, status = Open3.capture2e(borg_path, "--version")
      [output.strip, status]
    end

    # Check compatibility between Borg version and repository
    def check_compatibility
      raise BorgError, "Repository does not exist at #{@path}" unless exists?

      borg_version = self.class.borg_version(@borg_path)
      borg_major, borg_minor = borg_version.split(".").map(&:to_i)

      # Get repository version from config
      config_file = File.join(@path, "config")
      config_content = File.read(config_file)

      # Extract version from config (format: version = 1)
      repo_version = config_content.match(/version\s*=\s*(\d+)/)&.captures&.first&.to_i

      {
        borg_version: borg_version,
        repository_version: repo_version,
        compatible: check_version_compatibility(borg_major, borg_minor, repo_version)
      }
    end

    private

    def check_version_compatibility(borg_major, _borg_minor, repo_version)
      # Borg 1.x can ONLY work with repository version 1
      return true if borg_major == 1 && repo_version == 1
      return false if borg_major == 1 && repo_version == 2

      # Borg 2.x can work with repository version 2
      # Borg 2.x can READ from version 1 repos (read-only, for migration)
      # but for regular operations, version 2 repos are required
      return true if borg_major == 2 && repo_version == 2
      # Version 1 repos with Borg 2.x are limited (read-only for migration)
      return false if borg_major == 2 && repo_version == 1

      # Unknown combinations - assume incompatible
      false
    end

    def validate_repo_path(path)
      raise BorgError, "Repository path cannot be empty" if path.nil? || path.empty?

      normalized = File.expand_path(path)

      # Prevent repository creation in critical system directories
      forbidden = ["/bin", "/sbin", "/usr/bin", "/usr/sbin", "/etc", "/sys", "/proc", "/boot", "/dev"]
      forbidden.each do |forbidden_path|
        if normalized == forbidden_path || normalized.start_with?("#{forbidden_path}/")
          raise BorgError, "Invalid repository path: refusing to use system directory #{normalized}"
        end
      end

      normalized
    end

    def validate_borg_path(borg_path)
      raise BorgError, "Borg path cannot be empty" if borg_path.nil? || borg_path.to_s.strip.empty?

      # Check if the command is executable
      # For commands in PATH (like "borg"), use which to find the full path
      full_path = if borg_path.include?("/")
                    # Absolute or relative path provided
                    File.expand_path(borg_path)
                  else
                    # Command name only - search in PATH
                    find_in_path(borg_path)
                  end

      # Verify the executable exists and is actually executable
      unless full_path && File.executable?(full_path)
        raise BorgError, "Borg executable not found or not executable: #{borg_path}"
      end

      # Verify it's actually borg by checking version output
      begin
        output, status = self.class.execute_version_command(borg_path)
        unless status.success? && output.match?(/borg \d+\.\d+/)
          raise BorgError, "Command '#{borg_path}' does not appear to be Borg backup"
        end
      rescue StandardError => e
        raise BorgError, "Failed to verify Borg executable: #{e.message}"
      end

      borg_path
    end

    def find_in_path(command)
      ENV["PATH"].split(File::PATH_SEPARATOR).each do |directory|
        path = File.join(directory, command)
        return path if File.executable?(path)
      end
      nil
    end

    def execute_borg_command(cmd)
      env = {}
      env["BORG_PASSPHRASE"] = @passphrase if @passphrase

      # Apply Borg environment options from config (defaults to yes for backward compatibility)
      # Use strict boolean checking (only true/false allowed, default to true for backward compatibility)
      allow_relocated = @borg_options.fetch("allow_relocated_repo", true)
      allow_relocated = true unless allow_relocated == false # Normalize: only false disables, everything else enables

      allow_unencrypted = @borg_options.fetch("allow_unencrypted_repo", true)
      allow_unencrypted = true unless allow_unencrypted == false # Normalize: only false disables, everything else enables

      env["BORG_RELOCATED_REPO_ACCESS_IS_OK"] = allow_relocated ? "yes" : "no"
      env["BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK"] = allow_unencrypted ? "yes" : "no"

      # Redirect stdin from /dev/null to prevent interactive prompts
      result = system(env, *cmd, in: "/dev/null")
      raise BorgError, "Borg command failed: #{cmd.join(" ")}" unless result

      result
    end
  end
end
