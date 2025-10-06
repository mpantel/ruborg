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
end
