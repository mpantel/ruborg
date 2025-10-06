# frozen_string_literal: true

require "logger"
require "fileutils"

module Ruborg
  # Logging functionality for ruborg
  class RuborgLogger
    attr_reader :logger

    def initialize(log_file: nil)
      @log_file = log_file || default_log_file
      validate_and_ensure_log_directory
      @logger = Logger.new(@log_file, "daily")
      @logger.level = Logger::INFO
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime("%Y-%m-%d %H:%M:%S")}] #{severity}: #{msg}\n"
      end
    end

    def info(message)
      @logger.info(message)
    end

    def error(message)
      @logger.error(message)
    end

    def warn(message)
      @logger.warn(message)
    end

    def debug(message)
      @logger.debug(message)
    end

    private

    def default_log_file
      File.join(log_directory, "ruborg.log")
    end

    def log_directory
      File.expand_path("~/.ruborg/logs")
    end

    def validate_and_ensure_log_directory
      # Validate log file path for security
      normalized_path = File.expand_path(@log_file)

      # Prevent writing to sensitive system directories
      forbidden_paths = ["/bin", "/sbin", "/usr/bin", "/usr/sbin", "/etc", "/sys", "/proc", "/boot"]
      forbidden_paths.each do |forbidden|
        if normalized_path.start_with?("#{forbidden}/")
          raise ConfigError, "Invalid log path: refusing to write to system directory #{normalized_path}"
        end
      end

      # Ensure log directory exists
      log_dir = File.dirname(normalized_path)
      FileUtils.mkdir_p(log_dir) unless File.directory?(log_dir)
    end
  end
end
