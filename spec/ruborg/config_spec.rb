# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ruborg::Config do
  describe "#initialize" do
    it "loads a valid YAML configuration file" do
      config_data = {
        "repository" => "/path/to/repo",
        "backup_paths" => ["/path/to/backup"],
        "compression" => "lz4"
      }
      config_path = create_test_config(config_data)

      config = described_class.new(config_path)

      expect(config.data).to eq(config_data)
    end

    it "raises ConfigError when file does not exist" do
      expect {
        described_class.new("/non/existent/path.yml")
      }.to raise_error(Ruborg::ConfigError, /Configuration file not found/)
    end

    it "raises ConfigError for invalid YAML syntax" do
      config_path = File.join(tmpdir, "invalid.yml")
      File.write(config_path, "invalid: yaml: syntax:")

      expect {
        described_class.new(config_path)
      }.to raise_error(Ruborg::ConfigError, /Invalid YAML syntax/)
    end
  end

  describe "#repository" do
    it "returns the repository path" do
      config_data = { "repository" => "/path/to/repo" }
      config_path = create_test_config(config_data)

      config = described_class.new(config_path)

      expect(config.repository).to eq("/path/to/repo")
    end
  end

  describe "#backup_paths" do
    it "returns the backup paths" do
      config_data = { "backup_paths" => ["/path/1", "/path/2"] }
      config_path = create_test_config(config_data)

      config = described_class.new(config_path)

      expect(config.backup_paths).to eq(["/path/1", "/path/2"])
    end

    it "returns empty array when not specified" do
      config_path = create_test_config({})

      config = described_class.new(config_path)

      expect(config.backup_paths).to eq([])
    end
  end

  describe "#exclude_patterns" do
    it "returns the exclude patterns" do
      config_data = { "exclude_patterns" => ["*.tmp", "*.log"] }
      config_path = create_test_config(config_data)

      config = described_class.new(config_path)

      expect(config.exclude_patterns).to eq(["*.tmp", "*.log"])
    end

    it "returns empty array when not specified" do
      config_path = create_test_config({})

      config = described_class.new(config_path)

      expect(config.exclude_patterns).to eq([])
    end
  end

  describe "#compression" do
    it "returns the specified compression" do
      config_data = { "compression" => "zstd" }
      config_path = create_test_config(config_data)

      config = described_class.new(config_path)

      expect(config.compression).to eq("zstd")
    end

    it "returns default lz4 when not specified" do
      config_path = create_test_config({})

      config = described_class.new(config_path)

      expect(config.compression).to eq("lz4")
    end
  end

  describe "#encryption_mode" do
    it "returns the specified encryption mode" do
      config_data = { "encryption" => "keyfile" }
      config_path = create_test_config(config_data)

      config = described_class.new(config_path)

      expect(config.encryption_mode).to eq("keyfile")
    end

    it "returns default repokey when not specified" do
      config_path = create_test_config({})

      config = described_class.new(config_path)

      expect(config.encryption_mode).to eq("repokey")
    end
  end

  describe "#passbolt_integration" do
    it "returns passbolt configuration" do
      config_data = { "passbolt" => { "resource_id" => "test-uuid" } }
      config_path = create_test_config(config_data)

      config = described_class.new(config_path)

      expect(config.passbolt_integration).to eq({ "resource_id" => "test-uuid" })
    end

    it "returns empty hash when not specified" do
      config_path = create_test_config({})

      config = described_class.new(config_path)

      expect(config.passbolt_integration).to eq({})
    end
  end

  describe "#auto_init?" do
    it "returns true when auto_init is enabled" do
      config_data = { "auto_init" => true }
      config_path = create_test_config(config_data)

      config = described_class.new(config_path)

      expect(config.auto_init?).to be true
    end

    it "returns false when auto_init is disabled" do
      config_data = { "auto_init" => false }
      config_path = create_test_config(config_data)

      config = described_class.new(config_path)

      expect(config.auto_init?).to be false
    end

    it "returns false by default when not specified" do
      config_path = create_test_config({})

      config = described_class.new(config_path)

      expect(config.auto_init?).to be false
    end
  end

  describe "#log_file" do
    it "returns the log file path when specified" do
      config_data = { "log_file" => "/custom/path/ruborg.log" }
      config_path = create_test_config(config_data)

      config = described_class.new(config_path)

      expect(config.log_file).to eq("/custom/path/ruborg.log")
    end

    it "returns nil when not specified" do
      config_path = create_test_config({})

      config = described_class.new(config_path)

      expect(config.log_file).to be_nil
    end
  end
end