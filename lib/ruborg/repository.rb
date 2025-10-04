# frozen_string_literal: true

module Ruborg
  # Borg repository management
  class Repository
    attr_reader :path

    def initialize(path, passphrase: nil)
      @path = path
      @passphrase = passphrase
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

    def execute_borg_command(cmd)
      env = {}
      env["BORG_PASSPHRASE"] = @passphrase if @passphrase

      result = system(env, *cmd)
      raise BorgError, "Borg command failed: #{cmd.join(' ')}" unless result

      result
    end
  end
end