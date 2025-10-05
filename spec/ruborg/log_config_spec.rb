# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Log file configuration" do
  let(:custom_log_path) { File.join(tmpdir, "custom.log") }
  let(:config_data) do
    {
      "repository" => File.join(tmpdir, "repo"),
      "backup_paths" => [File.join(tmpdir, "source")],
      "log_file" => custom_log_path
    }
  end
  let(:config_file) { create_test_config(config_data) }

  before do
    # Mock borg operations to avoid actual borg calls
    allow_any_instance_of(Ruborg::Repository).to receive(:exists?).and_return(true)
    allow_any_instance_of(Ruborg::Repository).to receive(:list).and_return(true)
  end

  describe "CLI log file priority" do
    it "uses CLI --log option over config file" do
      cli_log_path = File.join(tmpdir, "cli.log")

      expect(Ruborg::RuborgLogger).to receive(:new).with(log_file: cli_log_path).and_call_original

      Ruborg::CLI.start(["list", "--config", config_file, "--log", cli_log_path])
    end

    it "uses config file log_file when --log not provided" do
      expect(Ruborg::RuborgLogger).to receive(:new).with(log_file: custom_log_path).and_call_original

      Ruborg::CLI.start(["list", "--config", config_file])
    end

    it "uses default when neither --log nor config log_file provided" do
      config_without_log = config_data.reject { |k| k == "log_file" }
      config_file_no_log = create_test_config(config_without_log)

      expect(Ruborg::RuborgLogger).to receive(:new).with(log_file: nil).and_call_original

      Ruborg::CLI.start(["list", "--config", config_file_no_log])
    end
  end

  describe "log file creation" do
    it "creates log file at configured path", :borg do
      FileUtils.mkdir_p(File.join(tmpdir, "source"))
      File.write(File.join(tmpdir, "source", "test.txt"), "content")

      # Create repo only if it doesn't exist
      repo = Ruborg::Repository.new(config_data["repository"], passphrase: "test")
      repo.create unless repo.exists?

      # Update config with passbolt mock
      config_with_passbolt = config_data.merge("passbolt" => { "resource_id" => "test-id" })
      File.write(config_file, config_with_passbolt.to_yaml)

      allow_any_instance_of(Ruborg::Passbolt).to receive(:get_password).and_return("test")
      allow_any_instance_of(Ruborg::Passbolt).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

      Ruborg::CLI.start(["backup", "--config", config_file])

      expect(File.exist?(custom_log_path)).to be true
      log_content = File.read(custom_log_path)
      expect(log_content).to include("Starting backup operation")
    end
  end
end
