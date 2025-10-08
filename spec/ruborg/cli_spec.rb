# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ruborg::CLI do
  let(:repo_path) { File.join(tmpdir, "cli_repo") }
  let(:passphrase) { "test-pass" }
  let(:config_data) do
    {
      "compression" => "lz4",
      "repositories" => [
        {
          "name" => "test-repo",
          "path" => repo_path,
          "sources" => [
            {
              "name" => "main",
              "paths" => [File.join(tmpdir, "backup_source")]
            }
          ]
        }
      ]
    }
  end
  let(:config_file) { create_test_config(config_data) }

  before do
    # Mock logger to avoid creating log files during tests
    allow_any_instance_of(Ruborg::RuborgLogger).to receive(:info)
    allow_any_instance_of(Ruborg::RuborgLogger).to receive(:error)
    allow_any_instance_of(Ruborg::RuborgLogger).to receive(:warn)
  end

  describe "init command", :borg do
    it "initializes a repository with passphrase" do
      expect do
        described_class.start(["init", repo_path, "--passphrase", passphrase])
      end.to output(/Repository initialized/).to_stdout
    end

    it "initializes a repository with passbolt" do
      allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
      allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

      expect do
        described_class.start(["init", repo_path, "--passbolt-id", "test-uuid"])
      end.to output(/Repository initialized/).to_stdout
    end

    it "exits with error when borg command fails" do
      # Use invalid path to trigger failure
      invalid_path = "/invalid/path/that/does/not/exist"

      expect do
        described_class.start(["init", invalid_path, "--passphrase", passphrase])
      end.to raise_error(SystemExit)
    end
  end

  describe "backup command", :borg do
    before do
      # Create repository first
      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      # Create source files
      FileUtils.mkdir_p(File.join(tmpdir, "backup_source"))
      File.write(File.join(tmpdir, "backup_source", "test.txt"), "content")

      # Update config to include passphrase via passbolt
      updated_config = config_data.merge("passbolt" => { "resource_id" => "test-id" })
      File.write(config_file, updated_config.to_yaml)

      # Mock passbolt
      allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
      allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)
    end

    it "creates a backup using config file" do
      expect do
        described_class.start(["backup", "--config", config_file, "--repository", "test-repo"])
      end.to output(/Backup created/).to_stdout
    end

    it "creates a backup with custom name" do
      expect do
        described_class.start(["backup", "--config", config_file, "--repository", "test-repo", "--name", "custom-backup"])
      end.to output(/Backup created/).to_stdout
    end

    it "removes source files when --remove-source is specified" do
      source_file = File.join(tmpdir, "backup_source", "test.txt")

      described_class.start(["backup", "--config", config_file, "--repository", "test-repo", "--remove-source"])

      expect(File.exist?(source_file)).to be false
    end
  end

  describe "list command", :borg do
    before do
      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      # Update config to include passphrase info or use passbolt mock
      updated_config = config_data.merge("passbolt" => { "resource_id" => "test-id" })
      File.write(config_file, updated_config.to_yaml)

      # Mock passbolt to return passphrase
      allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
      allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)
    end

    it "lists archives in repository" do
      expect do
        described_class.start(["list", "--config", config_file, "--repository", "test-repo"])
      end.not_to raise_error
    end
  end

  describe "restore command", :borg do
    let(:archive_name) { "test-archive" }
    let(:dest_dir) { File.join(tmpdir, "restore_dest") }

    before do
      # Create repository and backup
      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      FileUtils.mkdir_p(File.join(tmpdir, "backup_source"))
      File.write(File.join(tmpdir, "backup_source", "restore_test.txt"), "restore content")

      # Create backup using Backup class with mock config
      backup_config = double("BackupConfig")
      allow(backup_config).to receive_messages(backup_paths: [File.join(tmpdir, "backup_source")], exclude_patterns: [], compression: "lz4", encryption_mode: "repokey")

      backup = Ruborg::Backup.new(repo, config: backup_config)
      backup.create(name: archive_name)

      # Update config to include passphrase via passbolt
      updated_config = config_data.merge("passbolt" => { "resource_id" => "test-id" })
      File.write(config_file, updated_config.to_yaml)

      # Mock passbolt
      allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
      allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)
    end

    it "restores entire archive to destination" do
      expect do
        described_class.start(["restore", archive_name, "--config", config_file, "--repository", "test-repo", "--destination", dest_dir])
      end.to output(/Archive restored/).to_stdout
    end

    it "restores specific file from archive" do
      specific_file = File.join(tmpdir, "backup_source", "restore_test.txt")

      expect do
        described_class.start(["restore", archive_name, "--config", config_file, "--repository", "test-repo", "--destination", dest_dir, "--path", specific_file])
      end.to output(/Restored.*restore_test\.txt/).to_stdout
    end
  end

  describe "info command", :borg do
    before do
      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      # Update config to include passphrase via passbolt
      updated_config = config_data.merge("passbolt" => { "resource_id" => "test-id" })
      File.write(config_file, updated_config.to_yaml)

      # Mock passbolt
      allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
      allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)
    end

    it "shows repository information" do
      expect do
        described_class.start(["info", "--config", config_file, "--repository", "test-repo"])
      end.not_to raise_error
    end
  end

  describe "error handling" do
    it "exits with error message when config file not found" do
      expect do
        described_class.start(["backup", "--config", "/non/existent.yml"])
      end.to raise_error(SystemExit)
    end
  end

  describe "hostname validation", :borg do
    let(:current_hostname) { `hostname`.strip }

    before do
      # Create repository first
      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      # Create source files
      FileUtils.mkdir_p(File.join(tmpdir, "backup_source"))
      File.write(File.join(tmpdir, "backup_source", "test.txt"), "content")
    end

    context "when hostname matches" do
      it "allows backup operation" do
        config_with_hostname = config_data.merge(
          "hostname" => current_hostname,
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_hostname = create_test_config(config_with_hostname)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_hostname, "--repository", "test-repo"])
        end.to output(/Backup created/).to_stdout
      end
    end

    context "when hostname does not match" do
      it "raises ConfigError for backup command" do
        config_with_wrong_hostname = config_data.merge(
          "hostname" => "different-hostname.local",
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_wrong_hostname = create_test_config(config_with_wrong_hostname)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_wrong_hostname, "--repository", "test-repo"])
        end.to raise_error(SystemExit)
      end

      it "raises ConfigError for list command" do
        config_with_wrong_hostname = config_data.merge(
          "hostname" => "different-hostname.local",
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_wrong_hostname = create_test_config(config_with_wrong_hostname)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["list", "--config", config_file_with_wrong_hostname, "--repository", "test-repo"])
        end.to raise_error(SystemExit)
      end
    end

    context "when hostname is not configured" do
      it "allows backup operation without validation" do
        config_without_hostname = config_data.merge("passbolt" => { "resource_id" => "test-id" })
        config_file_without_hostname = create_test_config(config_without_hostname)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_without_hostname, "--repository", "test-repo"])
        end.to output(/Backup created/).to_stdout
      end
    end

    context "when repository has specific hostname" do
      it "validates repository-specific hostname over global" do
        config_with_repo_hostname = {
          "hostname" => "global-hostname.local",
          "compression" => "lz4",
          "passbolt" => { "resource_id" => "test-id" },
          "repositories" => [
            {
              "name" => "test-repo",
              "hostname" => current_hostname,
              "path" => repo_path,
              "sources" => [
                {
                  "name" => "main",
                  "paths" => [File.join(tmpdir, "backup_source")]
                }
              ]
            }
          ]
        }
        config_file_with_repo_hostname = create_test_config(config_with_repo_hostname)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_repo_hostname, "--repository", "test-repo"])
        end.to output(/Backup created/).to_stdout
      end

      it "raises error when repository-specific hostname does not match" do
        config_with_wrong_repo_hostname = {
          "hostname" => current_hostname,
          "compression" => "lz4",
          "passbolt" => { "resource_id" => "test-id" },
          "repositories" => [
            {
              "name" => "test-repo",
              "hostname" => "different-repo-hostname.local",
              "path" => repo_path,
              "sources" => [
                {
                  "name" => "main",
                  "paths" => [File.join(tmpdir, "backup_source")]
                }
              ]
            }
          ]
        }
        config_file_with_wrong_repo_hostname = create_test_config(config_with_wrong_repo_hostname)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_wrong_repo_hostname, "--repository", "test-repo"])
        end.to raise_error(SystemExit)
      end
    end
  end
end
