# frozen_string_literal: true

module Ruborg
  # Borg repository management
  class Repository
    attr_reader :path

    def initialize(path, passphrase: nil, borg_options: {})
      @path = validate_repo_path(path)
      @passphrase = passphrase
      @borg_options = borg_options
    end

    def exists?
      File.directory?(@path) && File.exist?(File.join(@path, "config"))
    end

    def create
      raise BorgError, "Repository already exists at #{@path}" if exists?

      cmd = ["borg", "init", "--encryption=repokey", @path]
      execute_borg_command(cmd)
    end

    def info
      raise BorgError, "Repository does not exist at #{@path}" unless exists?

      cmd = ["borg", "info", @path]
      execute_borg_command(cmd)
    end

    def list
      raise BorgError, "Repository does not exist at #{@path}" unless exists?

      cmd = ["borg", "list", @path]
      execute_borg_command(cmd)
    end

    private

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

    def execute_borg_command(cmd)
      env = {}
      env["BORG_PASSPHRASE"] = @passphrase if @passphrase

      # Apply Borg environment options from config (defaults to yes for backward compatibility)
      allow_relocated = @borg_options.fetch("allow_relocated_repo", true)
      allow_unencrypted = @borg_options.fetch("allow_unencrypted_repo", true)

      env["BORG_RELOCATED_REPO_ACCESS_IS_OK"] = allow_relocated ? "yes" : "no"
      env["BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK"] = allow_unencrypted ? "yes" : "no"

      # Redirect stdin from /dev/null to prevent interactive prompts
      result = system(env, *cmd, in: "/dev/null")
      raise BorgError, "Borg command failed: #{cmd.join(' ')}" unless result

      result
    end
  end
end