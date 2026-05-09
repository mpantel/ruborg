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
  end
end
