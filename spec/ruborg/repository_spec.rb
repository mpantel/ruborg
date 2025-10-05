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

      expect {
        repo.create
      }.not_to raise_error

      expect(repo.exists?).to be true
    end

    it "raises error if repository already exists" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      expect {
        repo.create
      }.to raise_error(Ruborg::BorgError, /already exists/)
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
  end

  describe "#info", :borg do
    it "raises error if repository does not exist" do
      repo = described_class.new(repo_path)

      expect {
        repo.info
      }.to raise_error(Ruborg::BorgError, /does not exist/)
    end

    it "executes borg info command" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      expect {
        repo.info
      }.not_to raise_error
    end
  end

  describe "#list", :borg do
    it "raises error if repository does not exist" do
      repo = described_class.new(repo_path)

      expect {
        repo.list
      }.to raise_error(Ruborg::BorgError, /does not exist/)
    end

    it "executes borg list command" do
      repo = described_class.new(repo_path, passphrase: passphrase)
      repo.create

      expect {
        repo.list
      }.not_to raise_error
    end
  end
end