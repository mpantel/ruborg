# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ruborg::Repository do
  let(:repo_path) { File.join(tmpdir, "lock_repo") }
  let(:passphrase) { "test-passphrase" }

  before { FileUtils.mkdir_p(repo_path) }

  describe "#locked?" do
    subject(:repo) { described_class.new(repo_path) }

    it "returns false when no lock files exist" do
      expect(repo.locked?).to be false
    end

    it "returns true when lock.exclusive exists" do
      FileUtils.touch(File.join(repo_path, "lock.exclusive"))
      expect(repo.locked?).to be true
    end

    it "returns true when lock.roster exists" do
      FileUtils.touch(File.join(repo_path, "lock.roster"))
      expect(repo.locked?).to be true
    end

    it "returns true when both lock files exist" do
      FileUtils.touch(File.join(repo_path, "lock.exclusive"))
      FileUtils.touch(File.join(repo_path, "lock.roster"))
      expect(repo.locked?).to be true
    end
  end

  describe "#break_lock", :borg do
    subject(:repo) { described_class.new(repo_path, passphrase: passphrase) }

    before { repo.create }

    it "succeeds on an unlocked repository" do
      expect { repo.break_lock }.not_to raise_error
    end

    it "clears a directory-style lock left by borg" do
      # Borg 1.4+ uses a directory; each holder creates a file inside it
      lock_dir = File.join(repo_path, "lock.exclusive")
      Dir.mkdir(lock_dir)
      FileUtils.touch(File.join(lock_dir, "testhost.99999.1"))

      expect(repo.locked?).to be true
      expect { repo.break_lock }.not_to raise_error
      expect(repo.locked?).to be false
    end

    it "raises BorgError when the repository does not exist" do
      absent = described_class.new(File.join(tmpdir, "no_such_repo"), passphrase: passphrase)
      expect { absent.break_lock }.to raise_error(Ruborg::BorgError, /does not exist/)
    end

    it "raises BorgError when borg version is below minimum" do
      allow(described_class).to receive(:borg_version).and_return("1.3.9")
      expect { repo.break_lock }.to raise_error(Ruborg::BorgError, /1\.4\.0.*required/)
    end
  end

  describe "#force_break_lock" do
    subject(:repo) { described_class.new(repo_path, passphrase: passphrase) }

    before do
      FileUtils.touch(File.join(repo_path, "config"))
    end

    it "removes lock.exclusive file" do
      FileUtils.touch(File.join(repo_path, "lock.exclusive"))
      repo.force_break_lock
      expect(File.exist?(File.join(repo_path, "lock.exclusive"))).to be false
    end

    it "removes lock.exclusive directory (Borg 1.4+ style)" do
      lock_dir = File.join(repo_path, "lock.exclusive")
      Dir.mkdir(lock_dir)
      FileUtils.touch(File.join(lock_dir, "testhost.99999.1"))

      repo.force_break_lock
      expect(File.exist?(lock_dir)).to be false
    end

    it "removes lock.roster when present" do
      FileUtils.touch(File.join(repo_path, "lock.roster"))
      repo.force_break_lock
      expect(File.exist?(File.join(repo_path, "lock.roster"))).to be false
    end

    it "removes both lock files when both exist" do
      FileUtils.touch(File.join(repo_path, "lock.exclusive"))
      FileUtils.touch(File.join(repo_path, "lock.roster"))
      removed = repo.force_break_lock
      expect(removed).to contain_exactly("lock.exclusive", "lock.roster")
      expect(repo.locked?).to be false
    end

    it "returns an empty array when no lock files exist" do
      expect(repo.force_break_lock).to eq([])
    end

    it "raises BorgError when the repository does not exist" do
      absent = described_class.new(File.join(tmpdir, "no_such_repo"), passphrase: passphrase)
      expect { absent.force_break_lock }.to raise_error(Ruborg::BorgError, /does not exist/)
    end
  end

  describe "lock_wait injection" do
    it "injects --lock-wait when lock_wait is configured" do
      repo = described_class.new(repo_path, lock_wait: 42)
      injected = repo.send(:inject_lock_wait, ["borg", "create", "::archive", "/src"])
      expect(injected).to eq(["borg", "--lock-wait", "42", "create", "::archive", "/src"])
    end

    it "does not inject --lock-wait when lock_wait is not configured" do
      repo = described_class.new(repo_path)
      cmd = ["borg", "create", "::archive", "/src"]
      expect(repo.send(:inject_lock_wait, cmd)).to eq(cmd)
    end

    it "does not inject --lock-wait for break-lock even when configured" do
      repo = described_class.new(repo_path, lock_wait: 42)
      cmd = ["borg", "break-lock", "/path/to/repo"]
      expect(repo.send(:inject_lock_wait, cmd)).to eq(cmd)
    end
  end

  describe "version check helpers" do
    subject(:repo) { described_class.new(repo_path) }

    it "accepts a version equal to the minimum" do
      expect(repo.send(:version_sufficient?, "1.2.0", "1.2.0")).to be true
    end

    it "accepts a version above the minimum" do
      expect(repo.send(:version_sufficient?, "1.4.4", "1.2.0")).to be true
    end

    it "rejects a version below the minimum" do
      expect(repo.send(:version_sufficient?, "1.1.9", "1.2.0")).to be false
    end

    it "handles double-digit minor versions correctly" do
      expect(repo.send(:version_sufficient?, "1.10.0", "1.9.0")).to be true
    end
  end
end
