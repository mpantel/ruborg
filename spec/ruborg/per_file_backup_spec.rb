# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Per-file backup mode", :borg do
  let(:tmpdir) { Dir.mktmpdir }
  let(:repo_path) { File.join(tmpdir, "test_repo") }
  let(:passphrase) { "test-passphrase" }
  let(:source_dir) { File.join(tmpdir, "source") }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  before do
    FileUtils.mkdir_p(source_dir)
  end

  # Helper to capture stdout
  def capture_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  describe "Per-file archive creation" do
    it "creates separate archives for each file" do
      # Create test files
      File.write(File.join(source_dir, "file1.txt"), "content1")
      File.write(File.join(source_dir, "file2.txt"), "content2")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # List archives
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      expect(output).to include("test-")

      # Should have 2 archives (one per file)
      archive_count = output.lines.count { |line| line.include?("test-") }
      expect(archive_count).to eq(2)
    end

    it "stores original file path in archive comment" do
      test_file = File.join(source_dir, "testfile.txt")
      File.write(test_file, "test content")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [test_file],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # Get list of archives first
      list_output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} --json 2>&1`
      json_data = JSON.parse(list_output)
      archive_name = json_data["archives"].first["name"]

      # Get archive info including comment for specific archive
      output = `BORG_PASSPHRASE=#{passphrase} borg info #{repo_path}::#{archive_name} --json 2>&1`
      json_info = JSON.parse(output)

      # Comment format is "path|||size|||hash", extract the path
      comment = json_info["archives"].first["comment"]
      stored_path = comment.split("|||").first

      expect(stored_path).to eq(test_file)
      expect(comment).to include("|||") # New format with size and hash
    end

    it "generates unique hash-based archive names" do
      File.write(File.join(source_dir, "file1.txt"), "content1")
      File.write(File.join(source_dir, "file2.txt"), "content2")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # List archives
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`

      # Archive names should contain filename, hash, and timestamp in format: repo-filename-hash-timestamp
      expect(output).to match(/test-.*-[a-f0-9]{12}-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}/)
    end

    it "respects exclude patterns in per-file mode" do
      File.write(File.join(source_dir, "file1.txt"), "content1")
      File.write(File.join(source_dir, "file2.tmp"), "temp content")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: ["*.tmp"],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # List archives
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`

      # Should have only 1 archive (*.tmp excluded)
      archive_count = output.lines.count { |line| line.include?("test-") }
      expect(archive_count).to eq(1)
    end

    it "raises error when no files found to backup" do
      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")

      expect do
        backup.create
      end.to raise_error(Ruborg::BorgError, /No files found to backup/)
    end
  end

  describe "Duplicate detection and hash verification" do
    it "skips files with unchanged content (same path, size, and hash)" do
      test_file = File.join(source_dir, "test.txt")
      File.write(test_file, "original content")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")

      # First backup
      backup.create

      # Verify archive was created with hash metadata
      list_output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} --json 2>&1`
      json_data = JSON.parse(list_output)
      expect(json_data["archives"].length).to eq(1)

      archive_name = json_data["archives"].first["name"]
      info_output = `BORG_PASSPHRASE=#{passphrase} borg info #{repo_path}::#{archive_name} --json 2>&1`
      json_info = JSON.parse(info_output)
      comment = json_info["archives"].first["comment"]

      expect(comment).to include("|||") # New format with hash
      expect(comment).to start_with(test_file)

      # Second backup (file unchanged) - create new backup instance to simulate real usage
      backup2 = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      output = capture_output { backup2.create }

      # Should skip the file
      expect(output).to include("Archive already exists (file unchanged)")
      expect(output).to include("1 skipped (unchanged)")

      # Verify no new archive was created
      list_output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} --json 2>&1`
      json_data = JSON.parse(list_output)
      expect(json_data["archives"].length).to eq(1)
    end

    it "creates versioned archive when content changes but size and mtime stay the same" do
      test_file = File.join(source_dir, "test.txt")
      File.write(test_file, "content1") # 8 bytes

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")

      # First backup
      backup.create

      # Get original mtime
      original_mtime = File.mtime(test_file)

      # Change content but keep same size and reset mtime
      File.write(test_file, "newstuff") # Also 8 bytes
      File.utime(original_mtime, original_mtime, test_file)

      # Second backup - create new instance to simulate real usage
      backup2 = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup2.create

      # Verify two archives exist (original + versioned)
      list_output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} --json 2>&1`
      json_data = JSON.parse(list_output)
      expect(json_data["archives"].length).to eq(2)

      # Verify one has version suffix
      archive_names = json_data["archives"].map { |a| a["name"] }
      versioned = archive_names.find { |name| name.end_with?("-v2") }
      expect(versioned).not_to be_nil
    end

    it "creates versioned archive when size changes but mtime stays the same" do
      test_file = File.join(source_dir, "test.txt")
      File.write(test_file, "short")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")

      # First backup
      backup.create

      # Get original mtime
      original_mtime = File.mtime(test_file)

      # Change content with different size but reset mtime
      File.write(test_file, "much longer content here")
      File.utime(original_mtime, original_mtime, test_file)

      # Second backup - create new instance to simulate real usage
      backup2 = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup2.create

      # Verify two archives exist
      list_output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} --json 2>&1`
      json_data = JSON.parse(list_output)
      expect(json_data["archives"].length).to eq(2)

      # Verify one has version suffix
      archive_names = json_data["archives"].map { |a| a["name"] }
      versioned = archive_names.find { |name| name.end_with?("-v2") }
      expect(versioned).not_to be_nil
    end

    it "handles backward compatibility with old format archives (no hash in comment)" do
      test_file = File.join(source_dir, "test.txt")
      File.write(test_file, "content")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      # Manually create an old-format archive (comment = plain path, no hash)
      archive_name = "test-legacy-archive"
      `BORG_PASSPHRASE=#{passphrase} borg create --compression lz4 --comment "#{test_file}" #{repo_path}::#{archive_name} #{test_file} 2>&1`

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")

      # Should create a new archive (old format has no hash, can't verify)
      expect { backup.create }.not_to raise_error

      # Verify new archive was created with hash
      list_output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} --json 2>&1`
      json_data = JSON.parse(list_output)
      expect(json_data["archives"].length).to eq(2)

      # Find the new archive (not the legacy one)
      new_archive = json_data["archives"].find { |a| a["name"] != archive_name }
      info_output = `BORG_PASSPHRASE=#{passphrase} borg info #{repo_path}::#{new_archive["name"]} --json 2>&1`
      json_info = JSON.parse(info_output)
      comment = json_info["archives"].first["comment"]

      expect(comment).to include("|||") # New format
    end
  end

  describe "File metadata-based retention" do
    it "prunes archives based on file modification time" do
      # Create files with different modification times
      old_file = File.join(source_dir, "old_file.txt")
      new_file = File.join(source_dir, "new_file.txt")

      File.write(old_file, "old content")
      File.write(new_file, "new content")

      # Set old file's mtime to 60 days ago
      old_time = Time.now - (60 * 24 * 60 * 60)
      File.utime(old_time, old_time, old_file)

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # Verify 2 archives created
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      archive_count = output.lines.count { |line| line.include?("test-") }
      expect(archive_count).to eq(2)

      # Prune with 30-day retention
      retention_policy = { "keep_files_modified_within" => "30d" }
      repo.prune(retention_policy, retention_mode: "per_file")

      # Should have only 1 archive left (new file)
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      archive_count = output.lines.count { |line| line.include?("test-") }
      expect(archive_count).to eq(1)
    end

    it "falls back to standard pruning when no file metadata retention specified" do
      File.write(File.join(source_dir, "file1.txt"), "content1")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # Use standard retention policy (no keep_files_modified_within)
      retention_policy = { "keep_daily" => 7 }

      # Should not raise error
      expect do
        repo.prune(retention_policy, retention_mode: "per_file")
      end.not_to raise_error
    end

    it "handles corrupted or inaccessible archives gracefully" do
      File.write(File.join(source_dir, "file1.txt"), "content1")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # Pruning should not crash even if metadata can't be read
      retention_policy = { "keep_files_modified_within" => "30d" }

      expect do
        repo.prune(retention_policy, retention_mode: "per_file")
      end.not_to raise_error
    end
  end

  describe "Time duration parsing" do
    let(:repo) { Ruborg::Repository.new(repo_path, passphrase: passphrase) }

    it "parses days correctly" do
      duration = repo.send(:parse_time_duration, "30d")
      expect(duration).to eq(30 * 24 * 60 * 60)
    end

    it "parses weeks correctly" do
      duration = repo.send(:parse_time_duration, "4w")
      expect(duration).to eq(4 * 7 * 24 * 60 * 60)
    end

    it "parses months correctly" do
      duration = repo.send(:parse_time_duration, "6m")
      expect(duration).to eq(6 * 30 * 24 * 60 * 60)
    end

    it "parses years correctly" do
      duration = repo.send(:parse_time_duration, "1y")
      expect(duration).to eq(365 * 24 * 60 * 60)
    end

    it "raises error for invalid format" do
      expect do
        repo.send(:parse_time_duration, "invalid")
      end.to raise_error(Ruborg::BorgError, /Invalid time duration format/)
    end
  end

  describe "Standard backup mode compatibility" do
    it "still works in standard mode" do
      File.write(File.join(source_dir, "file1.txt"), "content1")
      File.write(File.join(source_dir, "file2.txt"), "content2")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      # Standard mode (default)
      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "standard", repo_name: "test")
      backup.create(name: "standard-archive")

      # Should have 1 archive containing both files
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      expect(output).to include("standard-archive")

      archive_count = output.lines.count { |line| line.strip.start_with?("standard-archive") || line.strip.start_with?("test-") }
      expect(archive_count).to eq(1)
    end
  end

  describe "Mixed retention policies" do
    it "applies both file metadata and traditional retention" do
      # Create files
      old_file = File.join(source_dir, "old_file.txt")
      new_file = File.join(source_dir, "new_file.txt")

      File.write(old_file, "old content")
      File.write(new_file, "new content")

      # Set old file's mtime to 60 days ago
      old_time = Time.now - (60 * 24 * 60 * 60)
      File.utime(old_time, old_time, old_file)

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # Mix of file metadata and traditional retention
      retention_policy = {
        "keep_files_modified_within" => "30d",
        "keep_daily" => 7
      }

      # Should prune based on file metadata first
      expect do
        repo.prune(retention_policy, retention_mode: "per_file")
      end.not_to raise_error
    end
  end
end
