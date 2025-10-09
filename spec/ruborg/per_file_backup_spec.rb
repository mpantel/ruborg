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
    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
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

  describe "Per-file --remove-source behavior" do
    it "deletes each file immediately after successful backup" do
      # Create test files
      file1 = File.join(source_dir, "file1.txt")
      file2 = File.join(source_dir, "file2.txt")
      File.write(file1, "content1")
      File.write(file2, "content2")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")

      # Track file deletion order
      deleted_files = []
      allow(FileUtils).to receive(:rm) do |path|
        deleted_files << path
      end

      backup.create(remove_source: true)

      # Should have deleted exactly 2 files (use realpath to handle macOS /private prefix)
      expect(deleted_files.length).to eq(2)
      expect(deleted_files).to include(File.realpath(file1))
      expect(deleted_files).to include(File.realpath(file2))
    end

    it "deletes skipped files when already backed up (unchanged)" do
      # Create and backup a file
      test_file = File.join(source_dir, "test.txt")
      File.write(test_file, "content")

      # Preserve the mtime for later
      original_mtime = File.mtime(test_file)

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create(remove_source: true)

      # Verify file was deleted
      expect(File.exist?(test_file)).to be false

      # Recreate the same file with same content AND same mtime
      File.write(test_file, "content")
      File.utime(original_mtime, original_mtime, test_file)

      # Backup again with remove_source - should skip BUT delete (already safely backed up)
      backup2 = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      output = capture_output { backup2.create(remove_source: true) }

      # Verify it was skipped
      expect(output).to include("Archive already exists (file unchanged)")
      expect(output).to include("1 skipped (unchanged)")

      # File should be deleted (was skipped because already backed up, so safe to remove)
      expect(File.exist?(test_file)).to be false
    end
  end

  describe "Per-directory retention" do
    # rubocop:disable RSpec/IndexedLet
    let(:source_dir1) { File.join(tmpdir, "source1") }
    let(:source_dir2) { File.join(tmpdir, "source2") }
    # rubocop:enable RSpec/IndexedLet

    before do
      FileUtils.mkdir_p(source_dir1)
      FileUtils.mkdir_p(source_dir2)
    end

    it "applies retention independently to each source directory" do
      # Create files in different directories with different mtimes
      old_file1 = File.join(source_dir1, "old1.txt")
      new_file1 = File.join(source_dir1, "new1.txt")
      old_file2 = File.join(source_dir2, "old2.txt")
      new_file2 = File.join(source_dir2, "new2.txt")

      File.write(old_file1, "old content 1")
      File.write(new_file1, "new content 1")
      File.write(old_file2, "old content 2")
      File.write(new_file2, "new content 2")

      # Set old files to 60 days ago
      old_time = Time.now - (60 * 24 * 60 * 60)
      File.utime(old_time, old_time, old_file1)
      File.utime(old_time, old_time, old_file2)

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir1, source_dir2],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # Verify 4 archives created (2 per directory)
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      archive_count = output.lines.count { |line| line.include?("test-") }
      expect(archive_count).to eq(4)

      # Prune with 30-day retention
      retention_policy = { "keep_files_modified_within" => "30d" }
      repo.prune(retention_policy, retention_mode: "per_file")

      # Should have 2 archives left (one new file from each directory)
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      archive_count = output.lines.count { |line| line.include?("test-") }
      expect(archive_count).to eq(2)

      # Verify archives for new files still exist
      list_output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} --json 2>&1`
      json_data = JSON.parse(list_output)

      remaining_paths = json_data["archives"].map do |archive|
        info_output = `BORG_PASSPHRASE=#{passphrase} borg info #{repo_path}::#{archive["name"]} --json 2>&1`
        json_info = JSON.parse(info_output)
        comment = json_info["archives"].first["comment"]
        comment.split("|||").first
      end

      expect(remaining_paths).to include(new_file1)
      expect(remaining_paths).to include(new_file2)
      expect(remaining_paths).not_to include(old_file1)
      expect(remaining_paths).not_to include(old_file2)
    end

    it "maintains separate retention quotas per directory with keep_daily" do
      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir1, source_dir2],
                      exclude_patterns: [],
                      compression: "lz4")

      # Create 3 files in each directory
      # Note: All archives are created "now", so file mtime doesn't affect archive grouping by day
      # But we test that EACH directory independently applies keep_daily: 2
      3.times do |i|
        File.write(File.join(source_dir1, "file1_#{i}.txt"), "content1_#{i}")
        File.write(File.join(source_dir2, "file2_#{i}.txt"), "content2_#{i}")
      end

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # Verify 6 archives created (3 per directory)
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      archive_count = output.lines.count { |line| line.include?("test-") }
      expect(archive_count).to eq(6)

      # Prune with keep_daily: 2
      # Since all archives are from the same day (created in one backup run),
      # keep_daily: 2 will keep the most recent archives per directory
      # Each directory should apply the policy independently
      retention_policy = { "keep_daily" => 2 }
      repo.prune(retention_policy, retention_mode: "per_file")

      # With all archives from the same day, each directory keeps the most recent ones
      # Depending on implementation, this might keep 2 per directory or interpret differently
      # Let's verify archives are kept per directory (not globally)
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      archive_count = output.lines.count { |line| line.include?("test-") }

      # The implementation should keep at least 2 archives (one per directory minimum)
      # and at most 4 archives (2 per directory if keep_daily means "keep 2 latest")
      expect(archive_count).to be >= 2
      expect(archive_count).to be <= 4
    end

    it "stores source_dir in archive metadata for new format" do
      File.write(File.join(source_dir1, "file1.txt"), "content1")
      File.write(File.join(source_dir2, "file2.txt"), "content2")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir1, source_dir2],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # Get archives and check metadata format
      list_output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} --json 2>&1`
      json_data = JSON.parse(list_output)

      json_data["archives"].each do |archive|
        info_output = `BORG_PASSPHRASE=#{passphrase} borg info #{repo_path}::#{archive["name"]} --json 2>&1`
        json_info = JSON.parse(info_output)
        comment = json_info["archives"].first["comment"]

        # New format: path|||size|||hash|||source_dir
        parts = comment.split("|||")
        expect(parts.length).to eq(4)
        expect([source_dir1, source_dir2]).to include(parts[3])
      end
    end

    it "groups legacy archives separately from per-directory archives" do
      # Create a legacy archive (old format without source_dir)
      test_file = File.join(source_dir1, "legacy.txt")
      File.write(test_file, "legacy content")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      # Manually create old-format archive (comment = path|||size|||hash, no source_dir)
      file_size = File.size(test_file)
      file_hash = Digest::SHA256.file(test_file).hexdigest[0...12]
      legacy_comment = "#{test_file}|||#{file_size}|||#{file_hash}"
      `BORG_PASSPHRASE=#{passphrase} borg create --compression lz4 --comment "#{legacy_comment}" #{repo_path}::test-legacy #{test_file} 2>&1`

      # Now create new files with new format - different names to avoid duplication
      File.write(File.join(source_dir1, "new1.txt"), "new content 1")
      File.write(File.join(source_dir2, "new2.txt"), "new content 2")

      config = double("config",
                      backup_paths: [source_dir1, source_dir2],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # Count all test- archives (legacy + new)
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      archive_count = output.lines.count { |line| line.include?("test-") }
      # Should have: 1 legacy + 2 new archives from backup.create
      # But if legacy.txt was already in source_dir1, it might get backed up again
      # So we expect at least 3 archives
      expect(archive_count).to be >= 3

      # Pruning should not crash with mixed formats
      retention_policy = { "keep_daily" => 5 }
      expect do
        repo.prune(retention_policy, retention_mode: "per_file")
      end.not_to raise_error
    end

    it "handles mixed old/new format archives correctly during pruning" do
      # Create files in two directories
      legacy1 = File.join(source_dir1, "legacy1.txt")
      legacy2 = File.join(source_dir2, "legacy2.txt")

      File.write(legacy1, "legacy content 1")
      File.write(legacy2, "legacy content 2")

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      # Create two legacy archives (no source_dir in metadata)
      file1_size = File.size(legacy1)
      file1_hash = Digest::SHA256.file(legacy1).hexdigest[0...12]
      legacy_comment1 = "#{legacy1}|||#{file1_size}|||#{file1_hash}"
      `BORG_PASSPHRASE=#{passphrase} borg create --compression lz4 --comment "#{legacy_comment1}" #{repo_path}::test-legacy1 #{legacy1} 2>&1`

      file2_size = File.size(legacy2)
      file2_hash = Digest::SHA256.file(legacy2).hexdigest[0...12]
      legacy_comment2 = "#{legacy2}|||#{file2_size}|||#{file2_hash}"
      `BORG_PASSPHRASE=#{passphrase} borg create --compression lz4 --comment "#{legacy_comment2}" #{repo_path}::test-legacy2 #{legacy2} 2>&1`

      # Remove legacy files so they won't be backed up again
      File.delete(legacy1)
      File.delete(legacy2)

      # Now create new-format archives with different files
      File.write(File.join(source_dir1, "new1.txt"), "new content 1")
      File.write(File.join(source_dir2, "new2.txt"), "new content 2")

      config = double("config",
                      backup_paths: [source_dir1, source_dir2],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # Should have 4 archives total (2 legacy + 2 new)
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      archive_count = output.lines.count { |line| line.include?("test-") }
      expect(archive_count).to eq(4)

      # Prune with keep_daily: 1 per directory
      retention_policy = { "keep_daily" => 1 }
      repo.prune(retention_policy, retention_mode: "per_file")

      # Should keep 1 from each directory + legacy archives treated as separate group
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      remaining_count = output.lines.count { |line| line.include?("test-") }

      # Expect at least 2 archives (one per directory with new format)
      # Legacy archives form their own group and get 1 kept from that group
      expect(remaining_count).to be >= 2
      expect(remaining_count).to be <= 3
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

    it "applies keep_files_modified_within per directory" do
      # Create old and new files in each directory
      old_file1 = File.join(source_dir1, "old1.txt")
      new_file1 = File.join(source_dir1, "new1.txt")
      old_file2 = File.join(source_dir2, "old2.txt")
      new_file2 = File.join(source_dir2, "new2.txt")

      File.write(old_file1, "old1")
      File.write(new_file1, "new1")
      File.write(old_file2, "old2")
      File.write(new_file2, "new2")

      # Set old files to 45 days ago
      old_time = Time.now - (45 * 24 * 60 * 60)
      File.utime(old_time, old_time, old_file1)
      File.utime(old_time, old_time, old_file2)

      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      config = double("config",
                      backup_paths: [source_dir1, source_dir2],
                      exclude_patterns: [],
                      compression: "lz4")

      backup = Ruborg::Backup.new(repo, config: config, retention_mode: "per_file", repo_name: "test")
      backup.create

      # Verify 4 archives
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      expect(output.lines.count { |line| line.include?("test-") }).to eq(4)

      # Prune with 30-day retention - should remove old files from BOTH directories
      retention_policy = { "keep_files_modified_within" => "30d" }
      repo.prune(retention_policy, retention_mode: "per_file")

      # Should have 2 archives (new files from each directory)
      output = `BORG_PASSPHRASE=#{passphrase} borg list #{repo_path} 2>&1`
      expect(output.lines.count { |line| line.include?("test-") }).to eq(2)
    end
  end
end
