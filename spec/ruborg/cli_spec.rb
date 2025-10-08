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
      end.to raise_error(Ruborg::BorgError)
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

    it "removes source files when --remove-source is specified and allowed" do
      source_file = File.join(tmpdir, "backup_source", "test.txt")

      # Update config to allow remove_source
      updated_config = config_data.merge(
        "allow_remove_source" => true,
        "passbolt" => { "resource_id" => "test-id" }
      )
      File.write(config_file, updated_config.to_yaml)

      # Re-mock passbolt since we overwrote the config
      allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
      allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

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
      end.to raise_error(Ruborg::ConfigError)
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
        end.to raise_error(Ruborg::ConfigError)
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
        end.to raise_error(Ruborg::ConfigError)
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
        end.to raise_error(Ruborg::ConfigError)
      end
    end
  end

  describe "allow_remove_source validation", :borg do
    let(:current_hostname) { `hostname`.strip }

    before do
      # Create repository first
      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      # Create source files
      FileUtils.mkdir_p(File.join(tmpdir, "backup_source"))
      File.write(File.join(tmpdir, "backup_source", "test.txt"), "content")
    end

    context "when allow_remove_source is enabled" do
      it "allows --remove-source option" do
        config_with_allow = config_data.merge(
          "allow_remove_source" => true,
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_allow = create_test_config(config_with_allow)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_allow, "--repository", "test-repo", "--remove-source"])
        end.to output(/Sources removed/).to_stdout
      end
    end

    context "when allow_remove_source is not enabled" do
      it "prevents --remove-source option" do
        config_without_allow = config_data.merge(
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_without_allow = create_test_config(config_without_allow)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_without_allow, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "does not prevent backup without --remove-source" do
        config_without_allow = config_data.merge(
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_without_allow = create_test_config(config_without_allow)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_without_allow, "--repository", "test-repo"])
        end.to output(/Backup created/).to_stdout
      end
    end

    context "when repository-specific allow_remove_source is enabled" do
      it "allows --remove-source for specific repository" do
        config_with_repo_allow = {
          "allow_remove_source" => false, # Global disabled
          "compression" => "lz4",
          "passbolt" => { "resource_id" => "test-id" },
          "repositories" => [
            {
              "name" => "test-repo",
              "allow_remove_source" => true, # But enabled for this repo
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
        config_file_with_repo_allow = create_test_config(config_with_repo_allow)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_repo_allow, "--repository", "test-repo", "--remove-source"])
        end.to output(/Sources removed/).to_stdout
      end
    end

    context "when allow_remove_source has type confusion values" do
      it "blocks string 'false'" do
        config_with_string_false = config_data.merge(
          "allow_remove_source" => "false",
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_string = create_test_config(config_with_string_false)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_string, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "blocks string 'true'" do
        config_with_string_true = config_data.merge(
          "allow_remove_source" => "true",
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_string = create_test_config(config_with_string_true)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_string, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "blocks integer 1" do
        config_with_int = config_data.merge(
          "allow_remove_source" => 1,
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_int = create_test_config(config_with_int)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_int, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "blocks empty string" do
        config_with_empty = config_data.merge(
          "allow_remove_source" => "",
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_empty = create_test_config(config_with_empty)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_empty, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "blocks nil value" do
        config_with_nil = config_data.merge(
          "passbolt" => { "resource_id" => "test-id" }
        )
        # Don't set allow_remove_source at all (nil)
        config_file_with_nil = create_test_config(config_with_nil)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_nil, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "blocks boolean false" do
        config_with_false = config_data.merge(
          "allow_remove_source" => false,
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_false = create_test_config(config_with_false)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_false, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end
    end
  end

  describe "validate command" do
    context "with valid configuration" do
      it "passes validation with no errors" do
        valid_config = {
          "compression" => "lz4",
          "auto_init" => true,
          "auto_prune" => false,
          "allow_remove_source" => false,
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "auto_init" => true,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(valid_config)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to output(/Configuration is valid/).to_stdout
      end
    end

    context "with type confusion in allow_remove_source" do
      it "detects string 'true' instead of boolean" do
        invalid_config = {
          "allow_remove_source" => "true",
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "detects string 'false' instead of boolean" do
        invalid_config = {
          "allow_remove_source" => "false",
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "detects integer 1 instead of boolean" do
        invalid_config = {
          "auto_init" => 1,
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end
    end

    context "with type confusion in auto_init" do
      it "detects string value in auto_init" do
        invalid_config = {
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "auto_init" => "yes",
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end
    end

    context "with type confusion in auto_prune" do
      it "detects string value in auto_prune" do
        invalid_config = {
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "auto_prune" => "true",
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end
    end

    context "with warnings for borg_options" do
      it "shows warnings for non-boolean borg_options but doesn't fail" do
        config_with_warnings = {
          "borg_options" => {
            "allow_relocated_repo" => "yes",
            "allow_unencrypted_repo" => 1
          },
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(config_with_warnings)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to output(/WARNINGS/).to_stdout
      end
    end

    context "with multiple errors" do
      it "reports errors on config load" do
        multi_error_config = {
          "auto_init" => "true",
          "auto_prune" => 1,
          "allow_remove_source" => "false",
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "auto_init" => "yes",
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(multi_error_config)

        # Schema validation happens on config load, so it exits before validate command runs
        expect do
          described_class.start(["validate", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end
    end
  end

  describe "schema validation on config load" do
    context "when loading config with type errors" do
      it "fails on config load when allow_remove_source has wrong type" do
        invalid_config = {
          "allow_remove_source" => "true",
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["info", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "fails on config load when auto_init has wrong type" do
        invalid_config = {
          "auto_init" => 1,
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["info", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end
    end

    context "with valid types" do
      it "loads config successfully" do
        valid_config = {
          "auto_init" => true,
          "auto_prune" => false,
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(valid_config)

        expect do
          described_class.start(["info", "--config", config_file])
        end.to output(/RUBORG REPOSITORIES SUMMARY/).to_stdout
      end
    end
  end

  describe "allow_remove_source validation", :borg do
    let(:current_hostname) { `hostname`.strip }

    before do
      # Create repository first
      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      # Create source files
      FileUtils.mkdir_p(File.join(tmpdir, "backup_source"))
      File.write(File.join(tmpdir, "backup_source", "test.txt"), "content")
    end

    context "when allow_remove_source is enabled" do
      it "allows --remove-source option" do
        config_with_allow = config_data.merge(
          "allow_remove_source" => true,
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_allow = create_test_config(config_with_allow)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_allow, "--repository", "test-repo", "--remove-source"])
        end.to output(/Sources removed/).to_stdout
      end
    end

    context "when allow_remove_source is not enabled" do
      it "prevents --remove-source option" do
        config_without_allow = config_data.merge(
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_without_allow = create_test_config(config_without_allow)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_without_allow, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "does not prevent backup without --remove-source" do
        config_without_allow = config_data.merge(
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_without_allow = create_test_config(config_without_allow)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_without_allow, "--repository", "test-repo"])
        end.to output(/Backup created/).to_stdout
      end
    end

    context "when repository-specific allow_remove_source is enabled" do
      it "allows --remove-source for specific repository" do
        config_with_repo_allow = {
          "allow_remove_source" => false, # Global disabled
          "compression" => "lz4",
          "passbolt" => { "resource_id" => "test-id" },
          "repositories" => [
            {
              "name" => "test-repo",
              "allow_remove_source" => true, # But enabled for this repo
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
        config_file_with_repo_allow = create_test_config(config_with_repo_allow)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_repo_allow, "--repository", "test-repo", "--remove-source"])
        end.to output(/Sources removed/).to_stdout
      end
    end

    context "when allow_remove_source has type confusion values" do
      it "blocks string 'false'" do
        config_with_string_false = config_data.merge(
          "allow_remove_source" => "false",
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_string = create_test_config(config_with_string_false)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_string, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "blocks string 'true'" do
        config_with_string_true = config_data.merge(
          "allow_remove_source" => "true",
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_string = create_test_config(config_with_string_true)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_string, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "blocks integer 1" do
        config_with_int = config_data.merge(
          "allow_remove_source" => 1,
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_int = create_test_config(config_with_int)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_int, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "blocks empty string" do
        config_with_empty = config_data.merge(
          "allow_remove_source" => "",
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_empty = create_test_config(config_with_empty)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_empty, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "blocks nil value" do
        config_with_nil = config_data.merge(
          "passbolt" => { "resource_id" => "test-id" }
        )
        # Don't set allow_remove_source at all (nil)
        config_file_with_nil = create_test_config(config_with_nil)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_nil, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "blocks boolean false" do
        config_with_false = config_data.merge(
          "allow_remove_source" => false,
          "passbolt" => { "resource_id" => "test-id" }
        )
        config_file_with_false = create_test_config(config_with_false)

        # Mock passbolt
        allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
        allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

        expect do
          described_class.start(["backup", "--config", config_file_with_false, "--repository", "test-repo", "--remove-source"])
        end.to raise_error(Ruborg::ConfigError)
      end
    end
  end

  describe "validate command" do
    context "with valid configuration" do
      it "passes validation with no errors" do
        valid_config = {
          "compression" => "lz4",
          "auto_init" => true,
          "auto_prune" => false,
          "allow_remove_source" => false,
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "auto_init" => true,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(valid_config)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to output(/Configuration is valid/).to_stdout
      end
    end

    context "with type confusion in allow_remove_source" do
      it "detects string 'true' instead of boolean" do
        invalid_config = {
          "allow_remove_source" => "true",
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "detects string 'false' instead of boolean" do
        invalid_config = {
          "allow_remove_source" => "false",
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "detects integer 1 instead of boolean" do
        invalid_config = {
          "auto_init" => 1,
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end
    end

    context "with type confusion in auto_init" do
      it "detects string value in auto_init" do
        invalid_config = {
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "auto_init" => "yes",
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end
    end

    context "with type confusion in auto_prune" do
      it "detects string value in auto_prune" do
        invalid_config = {
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "auto_prune" => "true",
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end
    end

    context "with warnings for borg_options" do
      it "shows warnings for non-boolean borg_options but doesn't fail" do
        config_with_warnings = {
          "borg_options" => {
            "allow_relocated_repo" => "yes",
            "allow_unencrypted_repo" => 1
          },
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(config_with_warnings)

        expect do
          described_class.start(["validate", "--config", config_file])
        end.to output(/WARNINGS/).to_stdout
      end
    end

    context "with multiple errors" do
      it "reports errors on config load" do
        multi_error_config = {
          "auto_init" => "true",
          "auto_prune" => 1,
          "allow_remove_source" => "false",
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "auto_init" => "yes",
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(multi_error_config)

        # Schema validation happens on config load, so ConfigError is raised before validate command runs
        expect do
          described_class.start(["validate", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end
    end
  end

  describe "schema validation on config load" do
    context "when loading config with type errors" do
      it "fails on config load when allow_remove_source has wrong type" do
        invalid_config = {
          "allow_remove_source" => "true",
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["info", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end

      it "fails on config load when auto_init has wrong type" do
        invalid_config = {
          "auto_init" => 1,
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(invalid_config)

        expect do
          described_class.start(["info", "--config", config_file])
        end.to raise_error(Ruborg::ConfigError)
      end
    end

    context "with valid types" do
      it "loads config successfully" do
        valid_config = {
          "auto_init" => true,
          "auto_prune" => false,
          "repositories" => [
            {
              "name" => "test-repo",
              "path" => repo_path,
              "sources" => [{ "name" => "main", "paths" => ["/tmp/test"] }]
            }
          ]
        }
        config_file = create_test_config(valid_config)

        expect do
          described_class.start(["info", "--config", config_file])
        end.to output(/RUBORG REPOSITORIES SUMMARY/).to_stdout
      end
    end
  end

  describe "version command" do
    it "shows ruborg version" do
      expect do
        described_class.start(["version"])
      end.to output(/ruborg \d+\.\d+\.\d+/).to_stdout
    end

    it "includes version number from VERSION constant" do
      expect do
        described_class.start(["version"])
      end.to output(/#{Ruborg::VERSION}/).to_stdout
    end
  end

  describe "list --archive command", :borg do
    let(:archive_name) { "test-archive" }

    before do
      # Create repository and backup
      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      FileUtils.mkdir_p(File.join(tmpdir, "backup_source"))
      File.write(File.join(tmpdir, "backup_source", "test.txt"), "test content")

      # Create backup
      backup_config = double("BackupConfig")
      allow(backup_config).to receive_messages(
        backup_paths: [File.join(tmpdir, "backup_source")],
        exclude_patterns: [],
        compression: "lz4",
        encryption_mode: "repokey"
      )

      backup = Ruborg::Backup.new(repo, config: backup_config)
      backup.create(name: archive_name)

      # Update config
      updated_config = config_data.merge("passbolt" => { "resource_id" => "test-id" })
      File.write(config_file, updated_config.to_yaml)

      # Mock passbolt
      allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
      allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)
    end

    it "lists files in specific archive" do
      expect do
        described_class.start(["list", "--config", config_file, "--repository", "test-repo", "--archive", archive_name])
      end.not_to raise_error
    end

    it "raises error for non-existent archive" do
      expect do
        described_class.start(["list", "--config", config_file, "--repository", "test-repo", "--archive", "non-existent"])
      end.to raise_error(Ruborg::BorgError)
    end
  end

  describe "metadata command", :borg do
    let(:archive_name) { "test-archive" }

    before do
      # Create repository and backup
      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      FileUtils.mkdir_p(File.join(tmpdir, "backup_source"))
      test_file = File.join(tmpdir, "backup_source", "test.txt")
      File.write(test_file, "test content")

      # Create backup
      backup_config = double("BackupConfig")
      allow(backup_config).to receive_messages(
        backup_paths: [test_file],
        exclude_patterns: [],
        compression: "lz4",
        encryption_mode: "repokey"
      )

      backup = Ruborg::Backup.new(repo, config: backup_config)
      backup.create(name: archive_name)

      # Update config
      updated_config = config_data.merge("passbolt" => { "resource_id" => "test-id" })
      File.write(config_file, updated_config.to_yaml)

      # Mock passbolt
      allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
      allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)
    end

    it "shows file metadata from archive" do
      file_path = File.join(tmpdir, "backup_source", "test.txt")

      expect do
        described_class.start(["metadata", archive_name, "--config", config_file, "--repository", "test-repo", "--file", file_path])
      end.to output(/FILE METADATA/).to_stdout
    end

    it "shows size in human-readable format" do
      file_path = File.join(tmpdir, "backup_source", "test.txt")

      expect do
        described_class.start(["metadata", archive_name, "--config", config_file, "--repository", "test-repo", "--file", file_path])
      end.to output(/Size:/).to_stdout
    end

    it "raises error for non-existent archive" do
      expect do
        described_class.start(["metadata", "non-existent", "--config", config_file, "--repository", "test-repo"])
      end.to raise_error
    end
  end
end
