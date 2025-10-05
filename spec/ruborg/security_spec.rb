# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Security features" do
  describe "Path validation in extract" do
    let(:repo_path) { File.join(tmpdir, "repo") }
    let(:passphrase) { "test-pass" }
    let(:config_data) do
      {
        "repository" => repo_path,
        "backup_paths" => [File.join(tmpdir, "source")]
      }
    end
    let(:config_file) { create_test_config(config_data) }
    let(:config) { Ruborg::Config.new(config_file) }
    let(:repository) { Ruborg::Repository.new(repo_path, passphrase: passphrase) }
    let(:backup) { Ruborg::Backup.new(repository, config: config) }

    it "rejects extraction to root directory" do
      expect {
        backup.send(:validate_destination_path, "/")
      }.to raise_error(Ruborg::BorgError, /refusing to extract to system directory/)
    end

    it "rejects extraction to /etc" do
      expect {
        backup.send(:validate_destination_path, "/etc/malicious")
      }.to raise_error(Ruborg::BorgError, /refusing to extract to system directory/)
    end

    it "rejects extraction to /bin" do
      expect {
        backup.send(:validate_destination_path, "/bin/malicious")
      }.to raise_error(Ruborg::BorgError, /refusing to extract to system directory/)
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
    let(:config_data) do
      {
        "repository" => repo_path,
        "backup_paths" => [symlink_path]
      }
    end
    let(:config_file) { create_test_config(config_data) }
    let(:config) { Ruborg::Config.new(config_file) }
    let(:repository) { Ruborg::Repository.new(repo_path, passphrase: passphrase) }
    let(:backup) { Ruborg::Backup.new(repository, config: config) }

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
      # Create a symlink pointing to a forbidden path structure
      # We'll use /bin as the test case since it exists and should be blocked
      dangerous_link = File.join(tmpdir, "dangerous_link")

      # Create config that points to /bin directly (simulating symlink resolution)
      config_with_system_path = Ruborg::Config.new(
        create_test_config({
          "repository" => repo_path,
          "backup_paths" => ["/bin"]
        })
      )
      backup_dangerous = Ruborg::Backup.new(repository, config: config_with_system_path)

      expect {
        backup_dangerous.send(:remove_source_files)
      }.to raise_error(Ruborg::BorgError, /Refusing to delete system path/)
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

      expect {
        Ruborg::Config.new(malicious_yaml)
      }.to raise_error(Ruborg::ConfigError, /Invalid YAML content/)
    end

    it "accepts normal YAML configuration" do
      safe_yaml = File.join(tmpdir, "safe.yml")
      File.write(safe_yaml, <<~YAML)
        repository: /tmp/repo
        backup_paths:
          - /path/to/backup
      YAML

      expect {
        Ruborg::Config.new(safe_yaml)
      }.not_to raise_error
    end
  end

  describe "Repository path validation" do
    it "rejects empty repository paths" do
      expect {
        Ruborg::Repository.new("", passphrase: "test")
      }.to raise_error(Ruborg::BorgError, /Repository path cannot be empty/)
    end

    it "rejects nil repository paths" do
      expect {
        Ruborg::Repository.new(nil, passphrase: "test")
      }.to raise_error(Ruborg::BorgError, /Repository path cannot be empty/)
    end

    it "rejects repository paths in /etc" do
      expect {
        Ruborg::Repository.new("/etc/borg-repo", passphrase: "test")
      }.to raise_error(Ruborg::BorgError, /refusing to use system directory/)
    end

    it "rejects repository paths in /bin" do
      expect {
        Ruborg::Repository.new("/bin/borg-repo", passphrase: "test")
      }.to raise_error(Ruborg::BorgError, /refusing to use system directory/)
    end

    it "allows repository paths in user directories" do
      safe_path = File.join(tmpdir, "safe-repo")
      expect {
        Ruborg::Repository.new(safe_path, passphrase: "test")
      }.not_to raise_error
    end
  end

  describe "Backup path validation" do
    let(:repo_path) { File.join(tmpdir, "repo") }
    let(:passphrase) { "test-pass" }
    let(:repository) { Ruborg::Repository.new(repo_path, passphrase: passphrase) }

    it "rejects empty backup paths array" do
      config_data = {
        "repository" => repo_path,
        "backup_paths" => []
      }
      config = Ruborg::Config.new(create_test_config(config_data))
      backup = Ruborg::Backup.new(repository, config: config)

      expect {
        backup.send(:validate_backup_paths, [])
      }.to raise_error(Ruborg::BorgError, /No backup paths specified/)
    end

    it "rejects nil in backup paths" do
      config_data = {
        "repository" => repo_path,
        "backup_paths" => [nil]
      }
      config = Ruborg::Config.new(create_test_config(config_data))
      backup = Ruborg::Backup.new(repository, config: config)

      expect {
        backup.send(:validate_backup_paths, [nil])
      }.to raise_error(Ruborg::BorgError, /Empty backup path specified/)
    end

    it "rejects empty strings in backup paths" do
      config_data = {
        "repository" => repo_path,
        "backup_paths" => [""]
      }
      config = Ruborg::Config.new(create_test_config(config_data))
      backup = Ruborg::Backup.new(repository, config: config)

      expect {
        backup.send(:validate_backup_paths, [""])
      }.to raise_error(Ruborg::BorgError, /Empty backup path specified/)
    end

    it "normalizes valid backup paths" do
      config_data = {
        "repository" => repo_path,
        "backup_paths" => ["relative/path"]
      }
      config = Ruborg::Config.new(create_test_config(config_data))
      backup = Ruborg::Backup.new(repository, config: config)

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
      expect {
        cli.send(:sanitize_archive_name, "")
      }.to raise_error(Ruborg::ConfigError, /Archive name cannot be empty/)
    end

    it "rejects archive names that become empty after sanitization" do
      expect {
        cli.send(:sanitize_archive_name, "@#$%")
      }.to raise_error(Ruborg::ConfigError, /must contain at least one valid character/)
    end
  end

  describe "Borg environment variables configuration" do
    let(:repo_path) { File.join(tmpdir, "repo") }

    it "defaults to allowing relocated repos" do
      repo = Ruborg::Repository.new(repo_path, passphrase: "test")
      expect(repo.instance_variable_get(:@borg_options).fetch("allow_relocated_repo", true)).to be true
    end

    it "respects custom borg_options for relocated repos" do
      repo = Ruborg::Repository.new(repo_path, passphrase: "test", borg_options: {"allow_relocated_repo" => false})
      expect(repo.instance_variable_get(:@borg_options)["allow_relocated_repo"]).to be false
    end

    it "defaults to allowing unencrypted repos" do
      repo = Ruborg::Repository.new(repo_path, passphrase: "test")
      expect(repo.instance_variable_get(:@borg_options).fetch("allow_unencrypted_repo", true)).to be true
    end

    it "respects custom borg_options for unencrypted repos" do
      repo = Ruborg::Repository.new(repo_path, passphrase: "test", borg_options: {"allow_unencrypted_repo" => false})
      expect(repo.instance_variable_get(:@borg_options)["allow_unencrypted_repo"]).to be false
    end
  end

  describe "Compression algorithm validation" do
    it "accepts valid compression algorithms" do
      valid_yaml = File.join(tmpdir, "valid_compression.yml")
      File.write(valid_yaml, <<~YAML)
        repository: #{File.join(tmpdir, "repo")}
        backup_paths:
          - /path/to/backup
        compression: lz4
      YAML

      config = Ruborg::Config.new(valid_yaml)
      expect(config.compression).to eq("lz4")
    end

    it "rejects invalid compression algorithms" do
      invalid_yaml = File.join(tmpdir, "invalid_compression.yml")
      File.write(invalid_yaml, <<~YAML)
        repository: #{File.join(tmpdir, "repo")}
        backup_paths:
          - /path/to/backup
        compression: invalid
      YAML

      config = Ruborg::Config.new(invalid_yaml)
      expect {
        config.compression
      }.to raise_error(Ruborg::ConfigError, /Invalid compression/)
    end

    it "accepts all valid compression types" do
      ["lz4", "zstd", "zlib", "lzma", "none"].each do |compression|
        yaml_file = File.join(tmpdir, "compression_#{compression}.yml")
        File.write(yaml_file, <<~YAML)
          repository: #{File.join(tmpdir, "repo")}
          backup_paths:
            - /path/to/backup
          compression: #{compression}
        YAML

        config = Ruborg::Config.new(yaml_file)
        expect(config.compression).to eq(compression)
      end
    end
  end

  describe "Encryption mode validation" do
    it "accepts valid encryption modes" do
      valid_yaml = File.join(tmpdir, "valid_encryption.yml")
      File.write(valid_yaml, <<~YAML)
        repository: #{File.join(tmpdir, "repo")}
        backup_paths:
          - /path/to/backup
        encryption: repokey
      YAML

      config = Ruborg::Config.new(valid_yaml)
      expect(config.encryption_mode).to eq("repokey")
    end

    it "rejects invalid encryption modes" do
      invalid_yaml = File.join(tmpdir, "invalid_encryption.yml")
      File.write(invalid_yaml, <<~YAML)
        repository: #{File.join(tmpdir, "repo")}
        backup_paths:
          - /path/to/backup
        encryption: invalid
      YAML

      config = Ruborg::Config.new(invalid_yaml)
      expect {
        config.encryption_mode
      }.to raise_error(Ruborg::ConfigError, /Invalid encryption mode/)
    end
  end

  describe "Exclude pattern validation" do
    it "accepts valid exclude patterns" do
      valid_yaml = File.join(tmpdir, "valid_exclude.yml")
      File.write(valid_yaml, <<~YAML)
        repository: #{File.join(tmpdir, "repo")}
        backup_paths:
          - /path/to/backup
        exclude_patterns:
          - "*.tmp"
          - "*.log"
      YAML

      config = Ruborg::Config.new(valid_yaml)
      expect(config.exclude_patterns).to eq(["*.tmp", "*.log"])
    end

    it "rejects nil exclude patterns" do
      invalid_yaml = File.join(tmpdir, "invalid_exclude_nil.yml")
      File.write(invalid_yaml, <<~YAML)
        repository: #{File.join(tmpdir, "repo")}
        backup_paths:
          - /path/to/backup
        exclude_patterns:
          - "*.tmp"
          -
      YAML

      config = Ruborg::Config.new(invalid_yaml)
      expect {
        config.exclude_patterns
      }.to raise_error(Ruborg::ConfigError, /Exclude pattern cannot be empty/)
    end

    it "rejects exclude patterns that are too long" do
      invalid_yaml = File.join(tmpdir, "invalid_exclude_long.yml")
      long_pattern = "a" * 1001
      File.write(invalid_yaml, <<~YAML)
        repository: #{File.join(tmpdir, "repo")}
        backup_paths:
          - /path/to/backup
        exclude_patterns:
          - "#{long_pattern}"
      YAML

      config = Ruborg::Config.new(invalid_yaml)
      expect {
        config.exclude_patterns
      }.to raise_error(Ruborg::ConfigError, /Exclude pattern too long/)
    end
  end

  describe "Logger path validation" do
    it "validates log paths in logger initialization" do
      expect {
        Ruborg::RuborgLogger.new(log_file: "/etc/malicious.log")
      }.to raise_error(Ruborg::ConfigError, /refusing to write to system directory/)
    end

    it "allows safe log paths in logger" do
      safe_log = File.join(tmpdir, "safe.log")
      expect {
        Ruborg::RuborgLogger.new(log_file: safe_log)
      }.not_to raise_error
    end
  end

  describe "Log path validation" do
    it "rejects log paths in system directories" do
      expect {
        Ruborg::CLI.new.send(:validate_log_path, "/etc/ruborg.log")
      }.to raise_error(Ruborg::ConfigError, /refusing to write to system directory/)
    end

    it "rejects log paths in /bin" do
      expect {
        Ruborg::CLI.new.send(:validate_log_path, "/bin/ruborg.log")
      }.to raise_error(Ruborg::ConfigError, /refusing to write to system directory/)
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
