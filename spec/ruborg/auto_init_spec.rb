# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Auto-initialization feature", :borg do
  let(:repo_path) { File.join(tmpdir, "auto_init_repo") }
  let(:passphrase) { "test-passphrase" }
  let(:config_data) do
    {
      "compression" => "lz4",
      "auto_init" => true,
      "passbolt" => { "resource_id" => "test-id" },
      "repositories" => [
        {
          "name" => "test-repo",
          "path" => repo_path,
          "sources" => [
            {
              "name" => "main",
              "paths" => [File.join(tmpdir, "source")]
            }
          ]
        }
      ]
    }
  end
  let(:config_file) { create_test_config(config_data) }

  before do
    # Mock logger and passbolt
    allow_any_instance_of(Ruborg::RuborgLogger).to receive(:info)
    allow_any_instance_of(Ruborg::RuborgLogger).to receive(:error)
    allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return(passphrase)
    allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

    # Create source directory
    FileUtils.mkdir_p(File.join(tmpdir, "source"))
    File.write(File.join(tmpdir, "source", "test.txt"), "content")
  end

  describe "backup command with auto_init" do
    it "automatically initializes repository if it doesn't exist" do
      expect(File.exist?(File.join(repo_path, "config"))).to be false

      expect do
        Ruborg::CLI.start(["backup", "--config", config_file, "--repository", "test-repo"])
      end.to output(/Repository auto-initialized/).to_stdout

      expect(File.exist?(File.join(repo_path, "config"))).to be true
    end

    it "does not re-initialize if repository already exists" do
      # Create repo first
      repo = Ruborg::Repository.new(repo_path, passphrase: passphrase)
      repo.create

      expect do
        Ruborg::CLI.start(["backup", "--config", config_file, "--repository", "test-repo"])
      end.not_to output(/auto-initialized/).to_stdout
    end
  end

  describe "list command with auto_init" do
    it "automatically initializes repository if it doesn't exist" do
      expect(File.exist?(File.join(repo_path, "config"))).to be false

      expect do
        Ruborg::CLI.start(["list", "--config", config_file, "--repository", "test-repo"])
      end.to output(/Repository auto-initialized/).to_stdout

      expect(File.exist?(File.join(repo_path, "config"))).to be true
    end
  end

  describe "info command with auto_init" do
    it "automatically initializes repository if it doesn't exist" do
      expect(File.exist?(File.join(repo_path, "config"))).to be false

      expect do
        Ruborg::CLI.start(["info", "--config", config_file, "--repository", "test-repo"])
      end.to output(/Repository auto-initialized/).to_stdout

      expect(File.exist?(File.join(repo_path, "config"))).to be true
    end
  end

  describe "without auto_init enabled" do
    let(:config_data_no_auto) do
      {
        "compression" => "lz4",
        "auto_init" => false,
        "passbolt" => { "resource_id" => "test-id" },
        "repositories" => [
          {
            "name" => "test-repo",
            "path" => repo_path,
            "sources" => [
              {
                "name" => "main",
                "paths" => [File.join(tmpdir, "source")]
              }
            ]
          }
        ]
      }
    end
    let(:config_file_no_auto) { create_test_config(config_data_no_auto) }

    it "does not auto-initialize when disabled" do
      expect do
        Ruborg::CLI.start(["backup", "--config", config_file_no_auto, "--repository", "test-repo"])
      end.to raise_error(Ruborg::BorgError, /Repository does not exist/)

      expect(File.exist?(File.join(repo_path, "config"))).to be false
    end
  end
end
