# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Security features" do
  describe "Path validation in extract" do
    let(:repo_path) { File.join(tmpdir, "repo") }
    let(:passphrase) { "test-pass" }
    let(:config_file) { create_repository_config(repo_path, [File.join(tmpdir, "source")]) }
    let(:config) { Ruborg::Config.new(config_file) }
    let(:repo_config) { config.get_repository("test-repo") }
    let(:merged_config) { config.global_settings.merge(repo_config) }
    let(:backup_config) { Ruborg::CLI::BackupConfig.new(repo_config, merged_config) }
    let(:repository) { Ruborg::Repository.new(repo_path, passphrase: passphrase) }
    let(:backup) { Ruborg::Backup.new(repository, config: backup_config) }

    it "rejects extraction to root directory" do
      expect do
        backup.send(:validate_destination_path, "/")
      end.to raise_error(Ruborg::BorgError, /refusing to extract to system directory/)
    end

    it "rejects extraction to /etc" do
      expect do
        backup.send(:validate_destination_path, "/etc/malicious")
      end.to raise_error(Ruborg::BorgError, /refusing to extract to system directory/)
    end

    it "rejects extraction to /bin" do
      expect do
        backup.send(:validate_destination_path, "/bin/malicious")
      end.to raise_error(Ruborg::BorgError, /refusing to extract to system directory/)
    end

    it "allows extraction to safe directories" do
      safe_path = File.join(tmpdir, "safe_location")
      validated = backup.send(:validate_destination_path, safe_path)

      expect(validated).to eq(safe_path)
    end

    it "normalizes relative paths" do
      validated = backup.send(:validate_destination_path, "relative/path")

      expect(validated).to be_a(String)
      expect(validated).to start_with("/")
    end
  end

  describe "Symlink protection in remove_source_files", :borg do
    let(:repo_path) { File.join(tmpdir, "repo") }
    let(:passphrase) { "test-pass" }
    let(:real_dir) { File.join(tmpdir, "real_data") }
    let(:symlink_path) { File.join(tmpdir, "symlink_to_data") }
    let(:config_file) { create_repository_config(repo_path, [symlink_path]) }
    let(:config) { Ruborg::Config.new(config_file) }
    let(:repo_config) { config.get_repository("test-repo") }
    let(:merged_config) { config.global_settings.merge(repo_config) }
    let(:backup_config) { Ruborg::CLI::BackupConfig.new(repo_config, merged_config) }
    let(:repository) { Ruborg::Repository.new(repo_path, passphrase: passphrase) }
    let(:backup) { Ruborg::Backup.new(repository, config: backup_config) }

    before do
      FileUtils.mkdir_p(real_dir)
      File.write(File.join(real_dir, "important.txt"), "important data")
      File.symlink(real_dir, symlink_path)
      repository.create
    end

    it "follows symlinks and deletes real target" do
      backup.create(remove_source: true)

      # Symlink should be gone
      expect(File.exist?(symlink_path)).to be false
      # Real directory should also be gone (this is expected behavior)
      expect(File.exist?(real_dir)).to be false
    end

    it "refuses to delete system directories even via symlink" do
      # Create config that points to /bin directly (simulating symlink resolution)
      config_with_system_path = Ruborg::Config.new(create_repository_config(repo_path, ["/bin"]))
      repo_cfg = config_with_system_path.get_repository("test-repo")
      merged_cfg = config_with_system_path.global_settings.merge(repo_cfg)
      backup_cfg = Ruborg::CLI::BackupConfig.new(repo_cfg, merged_cfg)
      backup_dangerous = Ruborg::Backup.new(repository, config: backup_cfg)

      expect do
        backup_dangerous.send(:remove_source_files)
      end.to raise_error(Ruborg::BorgError, /Refusing to delete system path/)
    end
  end

  describe "YAML safe loading" do
    it "rejects YAML with arbitrary Ruby objects" do
      malicious_yaml = File.join(tmpdir, "malicious.yml")
      File.write(malicious_yaml, <<~YAML)
        repository: /tmp/repo
        backup_paths:
          - !ruby/object:Gem::Installer
              i: x
      YAML

      expect do
        Ruborg::Config.new(malicious_yaml)
      end.to raise_error(Ruborg::ConfigError, /Invalid YAML content/)
    end

    it "accepts normal YAML configuration" do
      safe_yaml = File.join(tmpdir, "safe.yml")
      File.write(safe_yaml, <<~YAML)
        repositories:
          - name: test
            path: /tmp/repo
            sources:
              - name: main
                paths:
                  - /path/to/backup
      YAML

      expect do
        Ruborg::Config.new(safe_yaml)
      end.not_to raise_error
    end
  end

  describe "Repository path validation" do
    it "rejects empty repository paths" do
      expect do
        Ruborg::Repository.new("", passphrase: "test")
      end.to raise_error(Ruborg::BorgError, /Repository path cannot be empty/)
    end

    it "rejects nil repository paths" do
      expect do
        Ruborg::Repository.new(nil, passphrase: "test")
      end.to raise_error(Ruborg::BorgError, /Repository path cannot be empty/)
    end

    it "rejects repository paths in /etc" do
      expect do
        Ruborg::Repository.new("/etc/borg-repo", passphrase: "test")
      end.to raise_error(Ruborg::BorgError, /refusing to use system directory/)
    end

    it "rejects repository paths in /bin" do
      expect do
        Ruborg::Repository.new("/bin/borg-repo", passphrase: "test")
      end.to raise_error(Ruborg::BorgError, /refusing to use system directory/)
    end

    it "allows repository paths in user directories" do
      safe_path = File.join(tmpdir, "safe-repo")
      expect do
        Ruborg::Repository.new(safe_path, passphrase: "test")
      end.not_to raise_error
    end
  end

  describe "Backup path validation" do
    let(:repo_path) { File.join(tmpdir, "repo") }
    let(:passphrase) { "test-pass" }
    let(:repository) { Ruborg::Repository.new(repo_path, passphrase: passphrase) }

    it "rejects empty backup paths array" do
      config = Ruborg::Config.new(create_repository_config(repo_path, []))
      repo_config = config.get_repository("test-repo")
      merged_config = config.global_settings.merge(repo_config)
      backup_config = Ruborg::CLI::BackupConfig.new(repo_config, merged_config)
      backup = Ruborg::Backup.new(repository, config: backup_config)

      expect do
        backup.send(:validate_backup_paths, [])
      end.to raise_error(Ruborg::BorgError, /No backup paths specified/)
    end

    it "rejects nil in backup paths" do
      config = Ruborg::Config.new(create_repository_config(repo_path, [nil]))
      repo_config = config.get_repository("test-repo")
      merged_config = config.global_settings.merge(repo_config)
      backup_config = Ruborg::CLI::BackupConfig.new(repo_config, merged_config)
      backup = Ruborg::Backup.new(repository, config: backup_config)

      expect do
        backup.send(:validate_backup_paths, [nil])
      end.to raise_error(Ruborg::BorgError, /Empty backup path specified/)
    end

    it "rejects empty strings in backup paths" do
      config = Ruborg::Config.new(create_repository_config(repo_path, [""]))
      repo_config = config.get_repository("test-repo")
      merged_config = config.global_settings.merge(repo_config)
      backup_config = Ruborg::CLI::BackupConfig.new(repo_config, merged_config)
      backup = Ruborg::Backup.new(repository, config: backup_config)

      expect do
        backup.send(:validate_backup_paths, [""])
      end.to raise_error(Ruborg::BorgError, /Empty backup path specified/)
    end

    it "normalizes valid backup paths" do
      config = Ruborg::Config.new(create_repository_config(repo_path, ["relative/path"]))
      repo_config = config.get_repository("test-repo")
      merged_config = config.global_settings.merge(repo_config)
      backup_config = Ruborg::CLI::BackupConfig.new(repo_config, merged_config)
      backup = Ruborg::Backup.new(repository, config: backup_config)

      validated = backup.send(:validate_backup_paths, ["relative/path"])
      expect(validated.first).to start_with("/")
    end
  end

  describe "Archive name sanitization" do
    let(:cli) { Ruborg::CLI.new }

    it "accepts valid archive names" do
      expect(cli.send(:sanitize_archive_name, "backup-2025-01-01")).to eq("backup-2025-01-01")
    end

    it "sanitizes special characters" do
      expect(cli.send(:sanitize_archive_name, "backup@#$%2025")).to eq("backup____2025")
    end

    it "rejects empty archive names" do
      expect do
        cli.send(:sanitize_archive_name, "")
      end.to raise_error(Ruborg::ConfigError, /Archive name cannot be empty/)
    end

    it "rejects archive names that become empty after sanitization" do
      expect do
        cli.send(:sanitize_archive_name, "@#$%")
      end.to raise_error(Ruborg::ConfigError, /must contain at least one valid character/)
    end
  end

  describe "Borg environment variables configuration" do
    let(:repo_path) { File.join(tmpdir, "repo") }

    it "defaults to allowing relocated repos" do
      repo = Ruborg::Repository.new(repo_path, passphrase: "test")
      expect(repo.instance_variable_get(:@borg_options).fetch("allow_relocated_repo", true)).to be true
    end

    it "respects custom borg_options for relocated repos" do
      repo = Ruborg::Repository.new(repo_path, passphrase: "test", borg_options: { "allow_relocated_repo" => false })
      expect(repo.instance_variable_get(:@borg_options)["allow_relocated_repo"]).to be false
    end

    it "defaults to allowing unencrypted repos" do
      repo = Ruborg::Repository.new(repo_path, passphrase: "test")
      expect(repo.instance_variable_get(:@borg_options).fetch("allow_unencrypted_repo", true)).to be true
    end

    it "respects custom borg_options for unencrypted repos" do
      repo = Ruborg::Repository.new(repo_path, passphrase: "test", borg_options: { "allow_unencrypted_repo" => false })
      expect(repo.instance_variable_get(:@borg_options)["allow_unencrypted_repo"]).to be false
    end
  end

  describe "Logger path validation" do
    it "validates log paths in logger initialization" do
      expect do
        Ruborg::RuborgLogger.new(log_file: "/etc/malicious.log")
      end.to raise_error(Ruborg::ConfigError, /refusing to write to system directory/)
    end

    it "allows safe log paths in logger" do
      safe_log = File.join(tmpdir, "safe.log")
      expect do
        Ruborg::RuborgLogger.new(log_file: safe_log)
      end.not_to raise_error
    end
  end

  describe "Log path validation" do
    it "rejects log paths in system directories" do
      expect do
        Ruborg::CLI.new.send(:validate_log_path, "/etc/ruborg.log")
      end.to raise_error(Ruborg::ConfigError, /refusing to write to system directory/)
    end

    it "rejects log paths in /bin" do
      expect do
        Ruborg::CLI.new.send(:validate_log_path, "/bin/ruborg.log")
      end.to raise_error(Ruborg::ConfigError, /refusing to write to system directory/)
    end

    it "allows log paths in user directories" do
      log_path = File.join(tmpdir, "logs", "ruborg.log")

      validated = Ruborg::CLI.new.send(:validate_log_path, log_path)

      expect(validated).to eq(log_path)
      expect(File.directory?(File.dirname(validated))).to be true
    end

    it "creates parent directories if they don't exist" do
      log_path = File.join(tmpdir, "deep", "nested", "logs", "ruborg.log")

      validated = Ruborg::CLI.new.send(:validate_log_path, log_path)

      expect(File.directory?(File.dirname(validated))).to be true
    end
  end

  describe "Passbolt command execution" do
    let(:passbolt) { Ruborg::Passbolt.new(resource_id: "test-id") }

    before do
      allow_any_instance_of(Ruborg::Passbolt).to receive(:system)
        .with("which passbolt > /dev/null 2>&1").and_return(true)
      require "open3"
    end

    it "uses Open3.capture3 for safe command execution" do
      expect(Open3).to receive(:capture3)
        .with("passbolt", "get", "resource", "test-id", "--json")
        .and_return(['{"password": "secret"}', "", double(success?: true)])

      passbolt.get_password
    end

    it "does not use shell interpolation" do
      # Verify no backticks or shell interpolation is used
      source = File.read("lib/ruborg/passbolt.rb")

      expect(source).not_to match(/`.*\#{/)
      expect(source).to include("Open3.capture3")
    end
  end
end
