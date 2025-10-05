# frozen_string_literal: true

require "logger"
require "fileutils"

module Ruborg
  # Logging functionality for ruborg
  class RuborgLogger
    attr_reader :logger

    def initialize(log_file: nil)
      @log_file = log_file || default_log_file
      ensure_log_directory
      @logger = Logger.new(@log_file, "daily")
      @logger.level = Logger::INFO
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
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
      dir = File.expand_path("~/.ruborg/logs")
      dir
    end

    def ensure_log_directory
      FileUtils.mkdir_p(File.dirname(@log_file)) unless File.directory?(File.dirname(@log_file))
    end
  end
end