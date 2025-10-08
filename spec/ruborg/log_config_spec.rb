# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Log file configuration" do
  let(:custom_log_path) { File.join(tmpdir, "custom.log") }
  let(:config_data) do
    {
      "log_file" => custom_log_path,
      "passbolt" => { "resource_id" => "test-id" },
      "repositories" => [
        {
          "name" => "test-repo",
          "path" => File.join(tmpdir, "repo"),
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
    # Mock borg operations to avoid actual borg calls
    allow_any_instance_of(Ruborg::Repository).to receive(:exists?).and_return(true)
    allow_any_instance_of(Ruborg::Repository).to receive(:list).and_return(true)

    # Mock passbolt to avoid CLI dependency
    allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return("test-pass")
    allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)
  end

  describe "CLI log file priority" do
    it "uses CLI --log option over config file" do
      cli_log_path = File.join(tmpdir, "cli.log")

      expect(Ruborg::RuborgLogger).to receive(:new).with(log_file: cli_log_path).and_call_original

      Ruborg::CLI.start(["list", "--config", config_file, "--repository", "test-repo", "--log", cli_log_path])
    end

    it "uses config file log_file when --log not provided" do
      expect(Ruborg::RuborgLogger).to receive(:new).with(log_file: custom_log_path).and_call_original

      Ruborg::CLI.start(["list", "--config", config_file, "--repository", "test-repo"])
    end

    it "uses default when neither --log nor config log_file provided" do
      config_without_log = config_data.reject { |k| k == "log_file" }
      config_file_no_log = create_test_config(config_without_log)

      expect(Ruborg::RuborgLogger).to receive(:new).with(log_file: nil).and_call_original

      Ruborg::CLI.start(["list", "--config", config_file_no_log, "--repository", "test-repo"])
    end
  end

  describe "log file creation" do
    it "creates log file at configured path", :borg do
      FileUtils.mkdir_p(File.join(tmpdir, "source"))
      File.write(File.join(tmpdir, "source", "test.txt"), "content")

      # Clear the global exists? mock for this test since we need actual repo
      allow_any_instance_of(Ruborg::Repository).to receive(:exists?).and_call_original

      # Create repo with same passphrase that Passbolt will return
      repo_path = config_data["repositories"][0]["path"]
      repo = Ruborg::Repository.new(repo_path, passphrase: "test-pass")
      repo.create unless repo.exists?

      Ruborg::CLI.start(["backup", "--config", config_file, "--repository", "test-repo"])

      expect(File.exist?(custom_log_path)).to be true
      log_content = File.read(custom_log_path)
      expect(log_content).to include("Starting backup operation")
    end
  end
end
