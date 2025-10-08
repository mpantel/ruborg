# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ruborg::Repository do
  let(:repo_path) { File.join(tmpdir, "test_repo") }
  let(:passphrase) { "test-passphrase" }

  describe "#initialize" do
    it "sets the repository path" do
      repo = described_class.new(repo_path)

      expect(repo.path).to eq(repo_path)
    end

    it "accepts an optional passphrase" do
      repo = described_class.new(repo_path, passphrase: passphrase)

      expect(repo.instance_variable_get(:@passphrase)).to eq(passphrase)
    end

    it "accepts an optional borg_path" do
      # Mock validation for test
      allow(described_class).to receive(:execute_version_command)
        .with("/custom/path/to/borg")
        .and_return(["borg 1.2.8", double(success?: true)])
      allow(File).to receive(:executable?).with("/custom/path/to/borg").and_return(true)

      repo = described_class.new(repo_path, borg_path: "/custom/path/to/borg")

      expect(repo.instance_variable_get(:@borg_path)).to eq("/custom/path/to/borg")
    end

    it "defaults to 'borg' when borg_path is not provided" do
      repo = described_class.new(repo_path)

      expect(repo.instance_variable_get(:@borg_path)).to eq("borg")
    end
  end

  describe "#exists?" do
    it "returns false when repository does not exist" do
      repo = described_class.new(repo_path)

      expect(repo.exists?).to be false
    end

    it "returns false when directory exists but is not a borg repo" do
      FileUtils.mkdir_p(repo_path)
      repo = described_class.new(repo_path)

      expect(repo.exists?).to be false
    end

    it "returns true when borg repository exists" do
      FileUtils.mkdir_p(repo_path)
      FileUtils.touch(File.join(repo_path, "config"))
      repo = described_class.new(repo_path)

      expect(repo.exists?).to be true
    end
  end

  describe "#create", :borg do
    it "creates a borg repository" do
      repo = described_class.new(repo_path, passphrase: passphrase)

      expect do
        repo.create
      end.not_to raise_error

      expect(repo.exists?).to be true
    end

    it "raises error if repository already exists" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      expect do
        repo.create
      end.to raise_error(Ruborg::BorgError, /already exists/)
    end

    it "passes passphrase to borg via environment" do
      repo = described_class.new(repo_path, passphrase: passphrase)

      expect(repo).to receive(:system).with(
        hash_including("BORG_PASSPHRASE" => passphrase),
        "borg", "init", "--encryption=repokey", repo_path,
        in: "/dev/null"
      ).and_return(true)

      repo.create
    end

    it "uses custom borg_path when provided" do
      custom_borg = "/custom/path/to/borg"
      # Mock validation for test
      allow(described_class).to receive(:execute_version_command)
        .with(custom_borg)
        .and_return(["borg 1.2.8", double(success?: true)])
      allow(File).to receive(:executable?).with(custom_borg).and_return(true)

      repo = described_class.new(repo_path, passphrase: passphrase, borg_path: custom_borg)

      expect(repo).to receive(:system).with(
        hash_including("BORG_PASSPHRASE" => passphrase),
        custom_borg, "init", "--encryption=repokey", repo_path,
        in: "/dev/null"
      ).and_return(true)

      repo.create
    end
  end

  describe "#info", :borg do
    it "raises error if repository does not exist" do
      repo = described_class.new(repo_path)

      expect do
        repo.info
      end.to raise_error(Ruborg::BorgError, /does not exist/)
    end

    it "executes borg info command" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      expect do
        repo.info
      end.not_to raise_error
    end
  end

  describe "#list", :borg do
    it "raises error if repository does not exist" do
      repo = described_class.new(repo_path)

      expect do
        repo.list
      end.to raise_error(Ruborg::BorgError, /does not exist/)
    end

    it "executes borg list command" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      expect do
        repo.list
      end.not_to raise_error
    end
  end

  describe "#prune", :borg do
    let(:retention_policy) do
      {
        "keep_hourly" => 24,
        "keep_daily" => 7,
        "keep_weekly" => 4,
        "keep_monthly" => 6,
        "keep_yearly" => 1
      }
    end

    it "raises error if repository does not exist" do
      repo = described_class.new(repo_path)

      expect do
        repo.prune(retention_policy)
      end.to raise_error(Ruborg::BorgError, /does not exist/)
    end

    it "raises error if no retention policy specified" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      expect do
        repo.prune({})
      end.to raise_error(Ruborg::BorgError, /No retention policy specified/)
    end

    it "executes borg prune with count-based retention options" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      expect(repo).to receive(:system).with(
        hash_including("BORG_PASSPHRASE" => passphrase),
        "borg", "prune", repo_path, "--stats",
        "--keep-hourly", "24",
        "--keep-daily", "7",
        "--keep-weekly", "4",
        "--keep-monthly", "6",
        "--keep-yearly", "1",
        in: "/dev/null"
      ).and_return(true)

      repo.prune(retention_policy)
    end

    it "executes borg prune with time-based retention options" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      time_policy = {
        "keep_within" => "7d",
        "keep_last" => "30d"
      }

      expect(repo).to receive(:system).with(
        hash_including("BORG_PASSPHRASE" => passphrase),
        "borg", "prune", repo_path, "--stats",
        "--keep-within", "7d",
        "--keep-last", "30d",
        in: "/dev/null"
      ).and_return(true)

      repo.prune(time_policy)
    end

    it "executes borg prune with combined retention options" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      combined_policy = {
        "keep_within" => "2d",
        "keep_daily" => 7,
        "keep_weekly" => 4,
        "keep_monthly" => 6
      }

      expect(repo).to receive(:system).with(
        hash_including("BORG_PASSPHRASE" => passphrase),
        "borg", "prune", repo_path, "--stats",
        "--keep-daily", "7",
        "--keep-weekly", "4",
        "--keep-monthly", "6",
        "--keep-within", "2d",
        in: "/dev/null"
      ).and_return(true)

      repo.prune(combined_policy)
    end
  end

  describe ".borg_version" do
    it "returns the installed Borg version" do
      process_status = instance_double(Process::Status, success?: true)
      allow(described_class).to receive(:execute_version_command).and_return(["borg 1.2.8", process_status])

      version = described_class.borg_version

      expect(version).to eq("1.2.8")
    end

    it "accepts custom borg_path parameter" do
      custom_borg = "/custom/path/to/borg"
      process_status = instance_double(Process::Status, success?: true)

      expect(described_class).to receive(:execute_version_command).with(custom_borg).and_return(["borg 2.0.0", process_status])

      version = described_class.borg_version(custom_borg)

      expect(version).to eq("2.0.0")
    end

    it "raises error if borg is not installed" do
      process_status = instance_double(Process::Status, success?: false)
      allow(described_class).to receive(:execute_version_command).and_return(["", process_status])

      expect do
        described_class.borg_version
      end.to raise_error(Ruborg::BorgError, /not installed/)
    end

    it "raises error if version cannot be parsed" do
      process_status = instance_double(Process::Status, success?: true)
      allow(described_class).to receive(:execute_version_command).and_return(["invalid output", process_status])

      expect do
        described_class.borg_version
      end.to raise_error(Ruborg::BorgError, /Could not parse/)
    end
  end

  describe "#check", :borg do
    it "raises error if repository does not exist" do
      repo = described_class.new(repo_path)

      expect do
        repo.check
      end.to raise_error(Ruborg::BorgError, /does not exist/)
    end

    it "executes borg check command" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      expect(repo).to receive(:system).with(
        hash_including("BORG_PASSPHRASE" => passphrase),
        "borg", "check", repo_path,
        in: "/dev/null"
      ).and_return(true)

      repo.check
    end
  end

  describe "#check_compatibility", :borg do
    it "raises error if repository does not exist" do
      repo = described_class.new(repo_path)

      expect do
        repo.check_compatibility
      end.to raise_error(Ruborg::BorgError, /does not exist/)
    end

    it "returns compatibility information for Borg 1.x and repo version 1" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      allow(described_class).to receive(:borg_version).and_return("1.2.8")

      result = repo.check_compatibility

      expect(result[:borg_version]).to eq("1.2.8")
      expect(result[:repository_version]).to eq(1)
      expect(result[:compatible]).to be true
    end

    it "detects incompatibility for Borg 1.x and repo version 2" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      # Mock config file with version 2
      config_file = File.join(repo_path, "config")
      original_content = File.read(config_file)
      File.write(config_file, original_content.gsub(/version\s*=\s*1/, "version = 2"))

      allow(described_class).to receive(:borg_version).and_return("1.2.8")

      result = repo.check_compatibility

      expect(result[:borg_version]).to eq("1.2.8")
      expect(result[:repository_version]).to eq(2)
      expect(result[:compatible]).to be false
    end
  end

  describe "logging functionality" do
    let(:logger) { instance_double(Ruborg::RuborgLogger) }

    before do
      allow(logger).to receive(:info)
      allow(logger).to receive(:warn)
      allow(logger).to receive(:error)
      allow(logger).to receive(:debug)
    end

    describe "repository creation logging", :borg do
      it "logs repository creation" do
        repo = described_class.new(repo_path, passphrase: passphrase, logger: logger)

        expect(logger).to receive(:info).with(/Creating Borg repository at #{Regexp.escape(repo_path)} with repokey encryption/)
        expect(logger).to receive(:info).with(/Repository created successfully at #{Regexp.escape(repo_path)}/)

        repo.create
      end
    end

    describe "pruning logging", :borg do
      let(:retention_policy) { { "keep_daily" => 7 } }

      before do
        repo = described_class.new(repo_path, passphrase: passphrase)
        repo.create
      end

      it "logs standard pruning operations" do
        repo = described_class.new(repo_path, passphrase: passphrase, logger: logger)

        # prune will execute borg command which logs via system, not via logger
        # but we can still test that logger is passed and available
        expect do
          repo.prune(retention_policy)
        end.not_to raise_error
      end
    end

    describe "per-file pruning logging", :borg do
      let(:source_dir) { File.join(tmpdir, "source") }

      before do
        # Create repository
        repo = described_class.new(repo_path, passphrase: passphrase)
        repo.create

        # Create a per-file backup
        FileUtils.mkdir_p(source_dir)
        File.write(File.join(source_dir, "test.txt"), "content")

        config = double("BackupConfig")
        allow(config).to receive_messages(
          backup_paths: [File.join(source_dir, "test.txt")],
          exclude_patterns: [],
          compression: "lz4"
        )

        backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
        backup.create
      end

      it "logs per-file pruning operations" do
        repo = described_class.new(repo_path, passphrase: passphrase, logger: logger)

        # Use keep_files_modified_within which triggers per-file pruning logic
        retention_policy = { "keep_files_modified_within" => "1d" }

        expect(logger).to receive(:info).with(/Pruning per-file archives based on file modification time/)
        expect(logger).to receive(:info).with(/Found \d+ archive\(s\) to evaluate for pruning/)

        repo.prune(retention_policy, retention_mode: "per_file")
      end

      it "logs when falling back to standard pruning" do
        repo = described_class.new(repo_path, passphrase: passphrase, logger: logger)

        # Use standard retention policy without keep_files_modified_within
        retention_policy = { "keep_daily" => 7 }

        expect(logger).to receive(:info).with(/No file metadata retention specified, using standard pruning/)

        repo.prune(retention_policy, retention_mode: "per_file")
      end

      it "logs archives marked for deletion" do
        repo = described_class.new(repo_path, passphrase: passphrase, logger: logger)

        # Use a very short retention to ensure deletion
        retention_policy = { "keep_files_modified_within" => "0d" }

        expect(logger).to receive(:info).with(/Pruning per-file archives/)
        expect(logger).to receive(:info).with(/Found \d+ archive\(s\) to evaluate/)
        expect(logger).to receive(:info).with(/Deleting \d+ archive\(s\)/)
        expect(logger).to receive(:debug).at_least(:once).with(/Archive .+ marked for deletion/)
        expect(logger).to receive(:debug).at_least(:once).with(/Deleting archive:/)
        expect(logger).to receive(:info).with(/Pruned \d+ archive\(s\) based on file modification time/)

        repo.prune(retention_policy, retention_mode: "per_file")
      end
    end
  end

  describe "#list_archive", :borg do
    let(:archive_name) { "test-archive" }

    before do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      # Create a simple backup
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      File.write(File.join(source_dir, "file1.txt"), "content1")

      system(
        { "BORG_PASSPHRASE" => passphrase },
        "borg", "create", "#{repo_path}::#{archive_name}", source_dir,
        in: "/dev/null",
        out: "/dev/null",
        err: "/dev/null"
      )
    end

    it "lists files in a specific archive" do
      repo = described_class.new(repo_path, passphrase: passphrase)

      expect do
        repo.list_archive(archive_name)
      end.not_to raise_error
    end

    it "raises error for empty archive name" do
      repo = described_class.new(repo_path, passphrase: passphrase)

      expect do
        repo.list_archive("")
      end.to raise_error(Ruborg::BorgError, /Archive name cannot be empty/)
    end

    it "raises error for non-existent archive" do
      repo = described_class.new(repo_path, passphrase: passphrase)

      expect do
        repo.list_archive("non-existent")
      end.to raise_error(Ruborg::BorgError)
    end
  end

  describe "#get_archive_info", :borg do
    let(:archive_name) { "test-archive" }

    before do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      # Create a simple backup
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      File.write(File.join(source_dir, "file1.txt"), "content1")

      system(
        { "BORG_PASSPHRASE" => passphrase },
        "borg", "create", "#{repo_path}::#{archive_name}", source_dir,
        in: "/dev/null",
        out: "/dev/null",
        err: "/dev/null"
      )
    end

    it "returns JSON metadata for archive" do
      repo = described_class.new(repo_path, passphrase: passphrase)

      result = repo.get_archive_info(archive_name)

      expect(result).to be_a(Hash)
      expect(result).to have_key("archives")
    end

    it "raises error for empty archive name" do
      repo = described_class.new(repo_path, passphrase: passphrase)

      expect do
        repo.get_archive_info("")
      end.to raise_error(Ruborg::BorgError, /Archive name cannot be empty/)
    end

    it "raises error for non-existent archive" do
      repo = described_class.new(repo_path, passphrase: passphrase)

      expect do
        repo.get_archive_info("non-existent")
      end.to raise_error(Ruborg::BorgError)
    end
  end

  describe "#get_file_metadata", :borg do
    let(:archive_name) { "test-archive" }
    let(:test_file) { File.join(tmpdir, "source", "file1.txt") }

    before do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      # Create a simple backup
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      File.write(test_file, "test content")

      system(
        { "BORG_PASSPHRASE" => passphrase },
        "borg", "create", "#{repo_path}::#{archive_name}", test_file,
        in: "/dev/null",
        out: "/dev/null",
        err: "/dev/null"
      )
    end

    it "returns metadata for specific file" do
      repo = described_class.new(repo_path, passphrase: passphrase)

      metadata = repo.get_file_metadata(archive_name, file_path: test_file)

      expect(metadata).to be_a(Hash)
      expect(metadata).to have_key("path")
      expect(metadata).to have_key("size")
    end

    it "raises error for empty archive name" do
      repo = described_class.new(repo_path, passphrase: passphrase)

      expect do
        repo.get_file_metadata("", file_path: test_file)
      end.to raise_error(Ruborg::BorgError, /Archive name cannot be empty/)
    end

    it "raises error when file not found in archive" do
      repo = described_class.new(repo_path, passphrase: passphrase)

      expect do
        repo.get_file_metadata(archive_name, file_path: "/non/existent/file.txt")
      end.to raise_error(Ruborg::BorgError, /not found in archive/)
    end
  end
end
