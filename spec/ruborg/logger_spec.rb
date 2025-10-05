# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ruborg::RuborgLogger do
  let(:log_file) { File.join(tmpdir, "test.log") }

  describe "#initialize" do
    it "creates a logger with specified log file" do
      logger = described_class.new(log_file: log_file)

      expect(logger.logger).to be_a(Logger)
    end

    it "uses default log file when not specified" do
      logger = described_class.new

      expect(logger.instance_variable_get(:@log_file)).to match(/\.ruborg\/logs\/ruborg\.log$/)
    end

    it "creates log directory if it doesn't exist" do
      log_dir = File.dirname(log_file)

      described_class.new(log_file: log_file)

      expect(File.directory?(log_dir)).to be true
    end

    it "sets log level to INFO" do
      logger = described_class.new(log_file: log_file)

      expect(logger.logger.level).to eq(Logger::INFO)
    end
  end

  describe "#info" do
    it "logs info messages" do
      logger = described_class.new(log_file: log_file)

      logger.info("Test info message")

      log_content = File.read(log_file)
      expect(log_content).to include("INFO: Test info message")
    end
  end

  describe "#error" do
    it "logs error messages" do
      logger = described_class.new(log_file: log_file)

      logger.error("Test error message")

      log_content = File.read(log_file)
      expect(log_content).to include("ERROR: Test error message")
    end
  end

  describe "#warn" do
    it "logs warning messages" do
      logger = described_class.new(log_file: log_file)

      logger.warn("Test warning message")

      log_content = File.read(log_file)
      expect(log_content).to include("WARN: Test warning message")
    end
  end

  describe "#debug" do
    it "does not log debug messages when level is INFO" do
      logger = described_class.new(log_file: log_file)

      logger.debug("Test debug message")

      log_content = File.read(log_file)
      expect(log_content).not_to include("DEBUG: Test debug message")
    end
  end

  describe "log format" do
    it "includes timestamp and severity" do
      logger = described_class.new(log_file: log_file)

      logger.info("Formatted message")

      log_content = File.read(log_file)
      expect(log_content).to match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] INFO: Formatted message/)
    end
  end
end
