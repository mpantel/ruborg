# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ruborg::Backup do
  let(:repo_path) { File.join(tmpdir, "backup_repo") }
  let(:passphrase) { "test-passphrase" }
  let(:repository) { Ruborg::Repository.new(repo_path, passphrase: passphrase) }

  # Create a simple config object for testing Backup class directly
  let(:backup_config) do
    config = double("BackupConfig")
    allow(config).to receive_messages(backup_paths: [File.join(tmpdir, "source")], exclude_patterns: ["*.tmp"], compression: "lz4", encryption_mode: "repokey")
    config
  end

  before(:each, :borg) do
    repository.create
  end

  describe "#initialize" do
    it "stores repository and config" do
      backup = described_class.new(repository, config: backup_config)

      expect(backup.instance_variable_get(:@repository)).to eq(repository)
      expect(backup.instance_variable_get(:@config)).to eq(backup_config)
    end
  end

  describe "#create", :borg do
    it "raises error if repository does not exist" do
      non_existent_repo = Ruborg::Repository.new("/non/existent", passphrase: passphrase)
      backup = described_class.new(non_existent_repo, config: backup_config)

      expect do
        backup.create
      end.to raise_error(Ruborg::BorgError, /does not exist/)
    end

    it "creates a backup with timestamp name by default" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      create_test_file("source/test.txt", "content")

      backup = described_class.new(repository, config: backup_config)

      expect do
        backup.create
      end.not_to raise_error
    end

    it "creates a backup with custom name" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      create_test_file("source/test.txt", "content")

      backup = described_class.new(repository, config: backup_config)

      expect do
        backup.create(name: "custom-backup")
      end.not_to raise_error
    end

    it "applies exclude patterns" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      create_test_file("source/keep.txt", "keep")
      create_test_file("source/exclude.tmp", "exclude")

      backup = described_class.new(repository, config: backup_config)

      expect(backup).to receive(:execute_borg_command) do |cmd|
        expect(cmd).to include("--exclude", "*.tmp")
        true
      end

      backup.create(name: "test-backup")
    end

    it "removes source files when remove_source is true" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      test_file = create_test_file("source/test.txt", "content")

      backup = described_class.new(repository, config: backup_config)
      backup.create(name: "test-backup", remove_source: true)

      expect(File.exist?(test_file)).to be false
    end

    it "keeps source files when remove_source is false" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      test_file = create_test_file("source/test.txt", "content")

      backup = described_class.new(repository, config: backup_config)
      backup.create(name: "test-backup", remove_source: false)

      expect(File.exist?(test_file)).to be true
    end
  end

  describe "#extract", :borg do
    let(:source_dir) { File.join(tmpdir, "source") }
    let(:dest_dir) { File.join(tmpdir, "restore") }

    before do
      FileUtils.mkdir_p(source_dir)
      create_test_file("source/test.txt", "test content")
      backup = described_class.new(repository, config: backup_config)
      backup.create(name: "test-archive")
    end

    it "raises error if repository does not exist" do
      non_existent_repo = Ruborg::Repository.new("/non/existent", passphrase: passphrase)
      backup = described_class.new(non_existent_repo, config: backup_config)

      expect do
        backup.extract("test-archive")
      end.to raise_error(Ruborg::BorgError, /does not exist/)
    end

    it "extracts entire archive to current directory" do
      backup = described_class.new(repository, config: backup_config)

      Dir.chdir(tmpdir) do
        expect do
          backup.extract("test-archive")
        end.not_to raise_error
      end
    end

    it "extracts archive to specified destination" do
      FileUtils.mkdir_p(dest_dir)
      backup = described_class.new(repository, config: backup_config)

      expect do
        backup.extract("test-archive", destination: dest_dir)
      end.not_to raise_error
    end

    it "creates destination directory if it doesn't exist" do
      backup = described_class.new(repository, config: backup_config)

      backup.extract("test-archive", destination: dest_dir)

      expect(File.directory?(dest_dir)).to be true
    end

    it "extracts specific file when path is provided" do
      backup = described_class.new(repository, config: backup_config)
      specific_file = File.join(source_dir, "test.txt")

      expect do
        backup.extract("test-archive", destination: dest_dir, path: specific_file)
      end.not_to raise_error
    end
  end

  describe "#delete", :borg do
    it "deletes an archive" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      create_test_file("source/test.txt", "content")

      backup = described_class.new(repository, config: backup_config)
      backup.create(name: "delete-me")

      expect do
        backup.delete("delete-me")
      end.not_to raise_error
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

    describe "per-file backup logging", :borg do
      it "logs each file being backed up in per-file mode" do
        source_dir = File.join(tmpdir, "source")
        FileUtils.mkdir_p(source_dir)
        create_test_file("source/file1.txt", "content1")
        create_test_file("source/file2.txt", "content2")

        backup = described_class.new(repository, config: backup_config, retention_mode: "per_file", repo_name: "test", logger: logger)

        expect(logger).to receive(:info).with(/Per-file mode: Found 2 file\(s\) to backup/)
        expect(logger).to receive(:info).with(/Backing up file 1\/2:/)
        expect(logger).to receive(:info).with(/Backing up file 2\/2:/)
        expect(logger).to receive(:info).with(/Per-file backup completed: 2 file\(s\) backed up/)

        backup.create
      end

      it "logs file count in per-file mode" do
        source_dir = File.join(tmpdir, "source")
        FileUtils.mkdir_p(source_dir)
        create_test_file("source/test.txt", "content")

        backup = described_class.new(repository, config: backup_config, retention_mode: "per_file", repo_name: "test", logger: logger)

        expect(logger).to receive(:info).with(/Per-file mode: Found 1 file\(s\) to backup/)

        backup.create
      end
    end

    describe "extraction logging", :borg do
      let(:source_dir) { File.join(tmpdir, "source") }
      let(:dest_dir) { File.join(tmpdir, "restore") }

      before do
        FileUtils.mkdir_p(source_dir)
        create_test_file("source/test.txt", "test content")
        backup = described_class.new(repository, config: backup_config)
        backup.create(name: "test-archive")
      end

      it "logs extraction of entire archive" do
        backup = described_class.new(repository, config: backup_config, logger: logger)

        expect(logger).to receive(:info).with(/Extracting test-archive to #{Regexp.escape(dest_dir)}/)
        expect(logger).to receive(:info).with(/Extraction completed successfully/)

        backup.extract("test-archive", destination: dest_dir)
      end

      it "logs extraction of specific file" do
        backup = described_class.new(repository, config: backup_config, logger: logger)
        specific_file = File.join(source_dir, "test.txt")

        expect(logger).to receive(:info).with(/Extracting #{Regexp.escape(specific_file)} from test-archive/)
        expect(logger).to receive(:info).with(/Extraction completed successfully/)

        backup.extract("test-archive", destination: dest_dir, path: specific_file)
      end
    end

    describe "archive deletion logging", :borg do
      it "logs archive deletion" do
        source_dir = File.join(tmpdir, "source")
        FileUtils.mkdir_p(source_dir)
        create_test_file("source/test.txt", "content")

        backup = described_class.new(repository, config: backup_config)
        backup.create(name: "delete-me")

        backup_with_logger = described_class.new(repository, config: backup_config, logger: logger)

        expect(logger).to receive(:info).with("Deleting archive: delete-me")
        expect(logger).to receive(:info).with("Archive deleted successfully: delete-me")

        backup_with_logger.delete("delete-me")
      end
    end

    describe "source file removal logging", :borg do
      it "logs source file removal" do
        source_dir = File.join(tmpdir, "source")
        FileUtils.mkdir_p(source_dir)
        test_file = create_test_file("source/test.txt", "content")

        backup = described_class.new(repository, config: backup_config, logger: logger)

        expect(logger).to receive(:info).with("Removing source files after successful backup")
        expect(logger).to receive(:info).with(/Removing (file|directory):/)
        expect(logger).to receive(:info).with(/Source file removal completed: 1 item\(s\) removed/)

        backup.create(name: "test-backup", remove_source: true)

        expect(File.exist?(test_file)).to be false
      end

      it "logs removal of directories" do
        source_dir = File.join(tmpdir, "source")
        FileUtils.mkdir_p(source_dir)
        create_test_file("source/test.txt", "content")

        backup = described_class.new(repository, config: backup_config, logger: logger)

        expect(logger).to receive(:info).with("Removing source files after successful backup")
        expect(logger).to receive(:info).with(/Removing directory:/)
        expect(logger).to receive(:info).with(/Source file removal completed: 1 item\(s\) removed/)

        backup.create(name: "test-backup", remove_source: true)
      end

      it "logs warnings for missing paths" do
        non_existent_config = double("BackupConfig")
        allow(non_existent_config).to receive_messages(
          backup_paths: [File.join(tmpdir, "nonexistent")],
          exclude_patterns: [],
          compression: "lz4",
          encryption_mode: "repokey"
        )

        # Create a dummy file so backup doesn't fail on "no paths"
        temp_source = File.join(tmpdir, "temp_source")
        FileUtils.mkdir_p(temp_source)
        File.write(File.join(temp_source, "dummy.txt"), "dummy")

        # Override backup_paths after create succeeds
        allow(non_existent_config).to receive(:backup_paths).and_return([File.join(tmpdir, "temp_source")])

        backup = described_class.new(repository, config: non_existent_config, logger: logger)
        backup.create(name: "test")

        # Now test removal with non-existent path
        allow(non_existent_config).to receive(:backup_paths).and_return([File.join(tmpdir, "nonexistent")])

        expect(logger).to receive(:info).with("Removing source files after successful backup")
        expect(logger).to receive(:warn).with(/Source path does not exist, skipping:/)
        expect(logger).to receive(:info).with(/Source file removal completed: 0 item\(s\) removed/)

        backup.send(:remove_source_files)
      end

      it "logs errors when refusing to delete system paths" do
        # Create a symlink to a forbidden path
        forbidden_link = File.join(tmpdir, "forbidden_link")
        File.symlink("/bin", forbidden_link)

        forbidden_config = double("BackupConfig")
        allow(forbidden_config).to receive_messages(
          backup_paths: [forbidden_link],
          exclude_patterns: [],
          compression: "lz4",
          encryption_mode: "repokey"
        )

        backup = described_class.new(repository, config: forbidden_config, logger: logger)

        expect(logger).to receive(:info).with("Removing source files after successful backup")
        expect(logger).to receive(:error).with(/Refusing to delete system path:/)

        expect do
          backup.send(:remove_source_files)
        end.to raise_error(Ruborg::BorgError, /Refusing to delete system path/)
      end
    end
  end
end
