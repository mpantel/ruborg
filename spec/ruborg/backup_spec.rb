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

        # Expect actual log messages that match implementation
        expect(logger).to receive(:info).with(/\[test\] Archived.*file1\.txt/).ordered
        expect(logger).to receive(:info).with(/\[test\] Archived.*file2\.txt/).ordered

        backup.create
      end

      it "logs file archived in per-file mode" do
        source_dir = File.join(tmpdir, "source")
        FileUtils.mkdir_p(source_dir)
        create_test_file("source/test.txt", "content")

        backup = described_class.new(repository, config: backup_config, retention_mode: "per_file", repo_name: "test", logger: logger)

        # Expect actual log message that matches implementation
        expect(logger).to receive(:info).with(/\[test\] Archived.*test\.txt/)

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

  describe "archive name truncation" do
    let(:backup) { described_class.new(repository, config: backup_config, retention_mode: "per_file", repo_name: "test") }

    describe "#truncate_with_extension" do
      it "returns filename unchanged if within max length" do
        result = backup.send(:truncate_with_extension, "short.txt", 50)
        expect(result).to eq("short.txt")
      end

      it "truncates basename while preserving extension" do
        long_filename = "very-long-database-name-with-many-tables.sql"
        result = backup.send(:truncate_with_extension, long_filename, 30)

        expect(result).to end_with(".sql")
        expect(result.length).to eq(30)
        expect(result).to match(/^very-long-database-name-wi\.sql$/)
      end

      it "truncates entire filename if extension is too long" do
        filename = "file.verylongextension"
        result = backup.send(:truncate_with_extension, filename, 10)

        expect(result.length).to eq(10)
        expect(result).to eq("file.veryl")
      end

      it "handles files without extension" do
        result = backup.send(:truncate_with_extension, "very-long-filename-without-extension", 20)

        expect(result.length).to eq(20)
        expect(result).to eq("very-long-filename-w")
      end

      it "handles files starting with dot" do
        result = backup.send(:truncate_with_extension, ".gitignore", 8)

        expect(result.length).to eq(8)
        expect(result).to eq(".gitigno")
      end

      it "returns empty string for zero max_length" do
        result = backup.send(:truncate_with_extension, "filename.txt", 0)
        expect(result).to eq("")
      end

      it "handles filenames with multiple dots" do
        result = backup.send(:truncate_with_extension, "archive.tar.gz", 10)

        expect(result).to end_with(".gz")
        expect(result.length).to eq(10)
      end
    end

    describe "#build_archive_name" do
      let(:timestamp) { "2025-10-08_19-05-07" }
      let(:path_hash) { "8b4c26d05aae" }

      it "builds normal archive name without truncation" do
        result = backup.send(:build_archive_name, "test", "database.sql", path_hash, timestamp)

        expect(result).to eq("test-database.sql-8b4c26d05aae-2025-10-08_19-05-07")
        expect(result.length).to be <= 255
      end

      it "truncates long filename to fit 255 character limit" do
        long_filename = ("a" * 300) + ".sql"
        result = backup.send(:build_archive_name, "test", long_filename, path_hash, timestamp)

        expect(result.length).to eq(255)
        expect(result).to include(".sql")
        expect(result).to start_with("test-")
        expect(result).to include(path_hash)
        expect(result).to include(timestamp)
      end

      it "handles very long repository name" do
        long_repo_name = "very-long-repository-name-" * 5
        result = backup.send(:build_archive_name, long_repo_name, "file.txt", path_hash, timestamp)

        expect(result.length).to be <= 255
        expect(result).to start_with(long_repo_name)
        expect(result).to include(path_hash)
        expect(result).to include(timestamp)
      end

      it "preserves extension when truncating" do
        long_filename = ("very-long-database-name-with-many-tables-and-descriptive-information" * 3) + ".sql"
        result = backup.send(:build_archive_name, "databases", long_filename, path_hash, timestamp)

        expect(result.length).to be <= 255
        expect(result).to include(".sql")
        expect(result).to include(path_hash)
        expect(result).to end_with(timestamp)
      end

      it "handles filename with no extension" do
        long_filename = "a" * 300
        result = backup.send(:build_archive_name, "test", long_filename, path_hash, timestamp)

        expect(result.length).to eq(255)
        expect(result).to start_with("test-")
      end

      it "ensures all components are present in archive name" do
        result = backup.send(:build_archive_name, "repo", "file.txt", path_hash, timestamp)

        expect(result).to include("repo")
        expect(result).to include("file.txt")
        expect(result).to include(path_hash)
        expect(result).to include(timestamp)
      end
    end

    describe "per-file archive creation with long filenames", :borg do
      it "creates archive with truncated name for very long filename" do
        source_dir = File.join(tmpdir, "source")
        FileUtils.mkdir_p(source_dir)

        # Create file with very long name
        long_filename = ("very-long-database-backup-with-descriptive-name-" * 5) + ".sql"
        create_test_file("source/#{long_filename}", "content")

        backup = described_class.new(repository, config: backup_config, retention_mode: "per_file", repo_name: "test")

        expect do
          backup.create
        end.not_to raise_error
      end

      it "preserves extension in archive name even for long filenames" do
        source_dir = File.join(tmpdir, "source")
        FileUtils.mkdir_p(source_dir)

        long_filename = ("a" * 250) + ".sql"
        create_test_file("source/#{long_filename}", "content")

        backup = described_class.new(repository, config: backup_config, retention_mode: "per_file", repo_name: "test")

        # Mock to capture the archive name
        allow(backup).to receive(:execute_borg_command) do |cmd|
          archive_name = cmd.find { |arg| arg.include?("::") }&.split("::")&.last
          expect(archive_name.length).to be <= 255
          expect(archive_name).to include(".sql")
          true
        end

        backup.create
      end

      it "uses file modification time in archive name (not backup creation time)" do
        source_dir = File.join(tmpdir, "source")
        FileUtils.mkdir_p(source_dir)

        # Create a file and set its mtime to a specific past time
        test_file = create_test_file("source/test.txt", "content")
        past_time = Time.new(2024, 5, 15, 14, 30, 45)
        File.utime(File.atime(test_file), past_time, test_file)

        backup = described_class.new(repository, config: backup_config, retention_mode: "per_file", repo_name: "test")

        # Mock to capture the archive name
        archive_name_captured = nil
        allow(backup).to receive(:execute_borg_command) do |cmd|
          archive_name_captured = cmd.find { |arg| arg.include?("::") }&.split("::")&.last
          true
        end

        backup.create

        # Verify the archive name contains the file's mtime, not the current time
        expect(archive_name_captured).to include("2024-05-15_14-30-45")
        expect(archive_name_captured).not_to include(Time.now.strftime("%Y-%m-%d"))
      end
    end
  end

  describe "console output and logging", :borg do
    let(:source_dir) { File.join(tmpdir, "source") }

    before do
      FileUtils.mkdir_p(source_dir)
      File.write(File.join(source_dir, "file1.txt"), "content1")
      File.write(File.join(source_dir, "file2.txt"), "content2")
    end

    it "shows repository header in console for standard backup" do
      backup = described_class.new(repository, config: backup_config, repo_name: "test-repo")

      expect do
        backup.create
      end.to output(/Repository: test-repo/).to_stdout
    end

    it "shows progress in console for standard backup" do
      backup = described_class.new(repository, config: backup_config, repo_name: "test-repo")

      expect do
        backup.create
      end.to output(/Creating archive/).to_stdout
    end

    it "shows completion message in console for standard backup" do
      backup = described_class.new(repository, config: backup_config, repo_name: "test-repo")

      expect do
        backup.create
      end.to output(/Archive created successfully/).to_stdout
    end

    it "logs archive creation with repository name", :borg do
      logger = instance_double(Ruborg::RuborgLogger)
      allow(logger).to receive(:info)

      backup = described_class.new(repository, config: backup_config, repo_name: "test-repo", logger: logger)

      expect(logger).to receive(:info).with(/\[test-repo\] Created archive/)

      backup.create
    end

    it "shows repository header in console for per-file backup" do
      backup = described_class.new(repository, config: backup_config, retention_mode: "per_file", repo_name: "test-repo")

      expect do
        backup.create
      end.to output(/Repository: test-repo/).to_stdout
    end

    it "shows file progress in console for per-file backup" do
      backup = described_class.new(repository, config: backup_config, retention_mode: "per_file", repo_name: "test-repo")

      expect do
        backup.create
      end.to output(%r{\[1/2\] Backing up:}).to_stdout
    end

    it "shows completion message for per-file backup" do
      backup = described_class.new(repository, config: backup_config, retention_mode: "per_file", repo_name: "test-repo")

      expect do
        backup.create
      end.to output(/Per-file backup completed/).to_stdout
    end

    it "logs each file with repository name in per-file mode", :borg do
      logger = instance_double(Ruborg::RuborgLogger)
      allow(logger).to receive(:info)

      backup = described_class.new(repository, config: backup_config, retention_mode: "per_file", repo_name: "test-repo", logger: logger)

      expect(logger).to receive(:info).with(/\[test-repo\] Archived.*in archive/).at_least(:once)

      backup.create
    end

    it "does not log repository header separator to logs" do
      logger = instance_double(Ruborg::RuborgLogger)
      allow(logger).to receive(:info)

      backup = described_class.new(repository, config: backup_config, repo_name: "test-repo", logger: logger)

      expect(logger).not_to receive(:info).with(/===/)

      backup.create
    end
  end

end
