# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backup integration with repositories", :borg do
  let(:repo1_path) { File.join(tmpdir, "repo1") }
  let(:repo2_path) { File.join(tmpdir, "repo2") }
  let(:passphrase) { "test-pass" }

  let(:config_data) do
    {
      "compression" => "lz4",
      "encryption" => "repokey",
      "auto_init" => true,
      "passbolt" => { "resource_id" => "global-id" },
      "repositories" => [
        {
          "name" => "documents",
          "path" => repo1_path,
          "sources" => [
            {
              "name" => "home-docs",
              "paths" => [File.join(tmpdir, "docs")],
              "exclude" => ["*.tmp"]
            },
            {
              "name" => "work-docs",
              "paths" => [File.join(tmpdir, "work")],
              "exclude" => ["*.log"]
            }
          ]
        },
        {
          "name" => "databases",
          "path" => repo2_path,
          "passbolt" => { "resource_id" => "db-specific-id" },
          "sources" => [
            {
              "name" => "mysql",
              "paths" => [File.join(tmpdir, "mysql")]
            }
          ]
        }
      ]
    }
  end

  let(:config_file) { create_test_config(config_data) }

  before do
    allow_any_instance_of(Ruborg::RuborgLogger).to receive(:info)
    allow_any_instance_of(Ruborg::RuborgLogger).to receive(:error)
    allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
    allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

    # Create source directories
    FileUtils.mkdir_p(File.join(tmpdir, "docs"))
    FileUtils.mkdir_p(File.join(tmpdir, "work"))
    FileUtils.mkdir_p(File.join(tmpdir, "mysql"))

    File.write(File.join(tmpdir, "docs", "file1.txt"), "content1")
    File.write(File.join(tmpdir, "work", "file2.txt"), "content2")
    File.write(File.join(tmpdir, "mysql", "dump.sql"), "sql content")
  end

  describe "Config class" do
    it "returns all repositories" do
      config = Ruborg::Config.new(config_file)

      expect(config.repositories.size).to eq(2)
      expect(config.repository_names).to eq(%w[documents databases])
    end

    it "gets specific repository by name" do
      config = Ruborg::Config.new(config_file)

      repo = config.get_repository("documents")

      expect(repo["name"]).to eq("documents")
      expect(repo["path"]).to eq(repo1_path)
    end

    it "returns global settings" do
      config = Ruborg::Config.new(config_file)

      settings = config.global_settings

      expect(settings["compression"]).to eq("lz4")
      expect(settings["passbolt"]["resource_id"]).to eq("global-id")
    end
  end

  describe "backup command" do
    it "requires --repository or --all" do
      expect do
        Ruborg::CLI.start(["backup", "--config", config_file])
      end.to raise_error(Ruborg::ConfigError)
    end

    it "backs up specific repository with --repository option" do
      expect do
        Ruborg::CLI.start(["backup", "--config", config_file, "--repository", "documents"])
      end.to output(/Backing up repository: documents/).to_stdout

      expect(File.exist?(File.join(repo1_path, "config"))).to be true
    end

    it "backs up all repositories with --all option" do
      expect do
        Ruborg::CLI.start(["backup", "--config", config_file, "--all"])
      end.to output(/Backing up repository: documents.*Backing up repository: databases/m).to_stdout

      expect(File.exist?(File.join(repo1_path, "config"))).to be true
      expect(File.exist?(File.join(repo2_path, "config"))).to be true
    end

    it "uses repository-specific passbolt when provided" do
      expect(Ruborg::Passbolt).to receive(:new)
        .with(hash_including(resource_id: "db-specific-id"))
        .and_call_original

      Ruborg::CLI.start(["backup", "--config", config_file, "--repository", "databases"])
    end
  end

  describe "BackupConfig wrapper" do
    it "aggregates paths from all sources" do
      repo_config = config_data["repositories"][0]
      backup_config = Ruborg::CLI::BackupConfig.new(repo_config, config_data)

      paths = backup_config.backup_paths

      expect(paths).to include(File.join(tmpdir, "docs"))
      expect(paths).to include(File.join(tmpdir, "work"))
    end

    it "combines exclude patterns from sources" do
      repo_config = config_data["repositories"][0]
      backup_config = Ruborg::CLI::BackupConfig.new(repo_config, config_data)

      patterns = backup_config.exclude_patterns

      expect(patterns).to include("*.tmp")
      expect(patterns).to include("*.log")
    end
  end
end
