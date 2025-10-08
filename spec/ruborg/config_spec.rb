# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ruborg::Config do
  describe "#initialize" do
    it "loads a valid multi-repository YAML configuration file" do
      config_path = create_repository_config(
        "/path/to/repo",
        ["/path/to/backup"]
      )

      config = described_class.new(config_path)

      expect(config.data).to be_a(Hash)
      expect(config.data["repositories"]).to be_an(Array)
    end

    it "raises ConfigError when file does not exist" do
      expect do
        described_class.new("/non/existent/path.yml")
      end.to raise_error(Ruborg::ConfigError, /Configuration file not found/)
    end

    it "raises ConfigError for invalid YAML syntax" do
      config_path = File.join(tmpdir, "invalid.yml")
      File.write(config_path, "invalid: yaml: syntax:")

      expect do
        described_class.new(config_path)
      end.to raise_error(Ruborg::ConfigError, /Invalid YAML syntax/)
    end

    it "raises ConfigError for single-repository format" do
      config_data = {
        "repository" => "/path/to/repo",
        "backup_paths" => ["/path/to/backup"]
      }
      config_path = create_test_config(config_data)

      expect do
        described_class.new(config_path)
      end.to raise_error(Ruborg::ConfigError, /Multi-repository format required/)
    end
  end

  describe "#repositories" do
    it "returns the repositories array" do
      config_path = create_repository_config("/path/to/repo", ["/path/to/backup"])
      config = described_class.new(config_path)

      expect(config.repositories).to be_an(Array)
      expect(config.repositories.first["name"]).to eq("test-repo")
    end

    it "returns empty array when no repositories specified" do
      config_data = { "repositories" => [] }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      expect(config.repositories).to eq([])
    end
  end

  describe "#get_repository" do
    it "returns the specified repository by name" do
      config_path = create_repository_config("/path/to/repo", ["/path/to/backup"])
      config = described_class.new(config_path)

      repo = config.get_repository("test-repo")

      expect(repo).to be_a(Hash)
      expect(repo["name"]).to eq("test-repo")
      expect(repo["path"]).to eq("/path/to/repo")
    end

    it "returns nil when repository not found" do
      config_path = create_repository_config("/path/to/repo", ["/path/to/backup"])
      config = described_class.new(config_path)

      repo = config.get_repository("nonexistent")

      expect(repo).to be_nil
    end
  end

  describe "#repository_names" do
    it "returns array of repository names" do
      config_data = {
        "repositories" => [
          { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] },
          { "name" => "repo2", "path" => "/path2", "sources" => [{ "name" => "s2", "paths" => ["/p2"] }] }
        ]
      }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      expect(config.repository_names).to eq(%w[repo1 repo2])
    end

    it "returns empty array when no repositories" do
      config_data = { "repositories" => [] }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      expect(config.repository_names).to eq([])
    end
  end

  describe "#global_settings" do
    it "returns global settings hash" do
      config_data = {
        "compression" => "lz4",
        "encryption" => "repokey",
        "auto_init" => true,
        "log_file" => "/var/log/ruborg.log",
        "passbolt" => { "resource_id" => "test-uuid" },
        "repositories" => [
          { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
        ]
      }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      settings = config.global_settings

      expect(settings["compression"]).to eq("lz4")
      expect(settings["encryption"]).to eq("repokey")
      expect(settings["auto_init"]).to be true
      expect(settings["log_file"]).to eq("/var/log/ruborg.log")
      expect(settings["passbolt"]).to eq({ "resource_id" => "test-uuid" })
    end

    it "returns empty hash when no global settings" do
      config_data = {
        "repositories" => [
          { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
        ]
      }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      settings = config.global_settings

      expect(settings).to be_a(Hash)
    end

    it "includes hostname in global settings" do
      config_data = {
        "hostname" => "myserver.local",
        "compression" => "lz4",
        "repositories" => [
          { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
        ]
      }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      settings = config.global_settings

      expect(settings["hostname"]).to eq("myserver.local")
    end
  end
end
