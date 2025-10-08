# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ruborg::Config do
  describe "#initialize" do
    it "loads a valid multi-repository YAML configuration file" do
      config_path = create_repository_config(
        "/path/to/repo",
        ["/path/to/backup"]
      )

      config = described_class.new(config_path)

      expect(config.data).to be_a(Hash)
      expect(config.data["repositories"]).to be_an(Array)
    end

    it "raises ConfigError when file does not exist" do
      expect do
        described_class.new("/non/existent/path.yml")
      end.to raise_error(Ruborg::ConfigError, /Configuration file not found/)
    end

    it "raises ConfigError for invalid YAML syntax" do
      config_path = File.join(tmpdir, "invalid.yml")
      File.write(config_path, "invalid: yaml: syntax:")

      expect do
        described_class.new(config_path)
      end.to raise_error(Ruborg::ConfigError, /Invalid YAML syntax/)
    end

    it "raises ConfigError for single-repository format" do
      config_data = {
        "repository" => "/path/to/repo",
        "backup_paths" => ["/path/to/backup"]
      }
      config_path = create_test_config(config_data)

      expect do
        described_class.new(config_path)
      end.to raise_error(Ruborg::ConfigError, /Multi-repository format required/)
    end
  end

  describe "#repositories" do
    it "returns the repositories array" do
      config_path = create_repository_config("/path/to/repo", ["/path/to/backup"])
      config = described_class.new(config_path)

      expect(config.repositories).to be_an(Array)
      expect(config.repositories.first["name"]).to eq("test-repo")
    end

    it "returns empty array when no repositories specified" do
      config_data = { "repositories" => [] }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      expect(config.repositories).to eq([])
    end
  end

  describe "#get_repository" do
    it "returns the specified repository by name" do
      config_path = create_repository_config("/path/to/repo", ["/path/to/backup"])
      config = described_class.new(config_path)

      repo = config.get_repository("test-repo")

      expect(repo).to be_a(Hash)
      expect(repo["name"]).to eq("test-repo")
      expect(repo["path"]).to eq("/path/to/repo")
    end

    it "returns nil when repository not found" do
      config_path = create_repository_config("/path/to/repo", ["/path/to/backup"])
      config = described_class.new(config_path)

      repo = config.get_repository("nonexistent")

      expect(repo).to be_nil
    end
  end

  describe "#repository_names" do
    it "returns array of repository names" do
      config_data = {
        "repositories" => [
          { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] },
          { "name" => "repo2", "path" => "/path2", "sources" => [{ "name" => "s2", "paths" => ["/p2"] }] }
        ]
      }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      expect(config.repository_names).to eq(%w[repo1 repo2])
    end

    it "returns empty array when no repositories" do
      config_data = { "repositories" => [] }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      expect(config.repository_names).to eq([])
    end
  end

  describe "#global_settings" do
    it "returns global settings hash" do
      config_data = {
        "compression" => "lz4",
        "encryption" => "repokey",
        "auto_init" => true,
        "log_file" => "/var/log/ruborg.log",
        "passbolt" => { "resource_id" => "test-uuid" },
        "repositories" => [
          { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
        ]
      }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      settings = config.global_settings

      expect(settings["compression"]).to eq("lz4")
      expect(settings["encryption"]).to eq("repokey")
      expect(settings["auto_init"]).to be true
      expect(settings["log_file"]).to eq("/var/log/ruborg.log")
      expect(settings["passbolt"]).to eq({ "resource_id" => "test-uuid" })
    end

    it "returns empty hash when no global settings" do
      config_data = {
        "repositories" => [
          { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
        ]
      }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      settings = config.global_settings

      expect(settings).to be_a(Hash)
    end

    it "includes hostname in global settings" do
      config_data = {
        "hostname" => "myserver.local",
        "compression" => "lz4",
        "repositories" => [
          { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
        ]
      }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      settings = config.global_settings

      expect(settings["hostname"]).to eq("myserver.local")
    end

    it "includes borg_path in global settings" do
      config_data = {
        "borg_path" => "/usr/local/bin/borg",
        "compression" => "lz4",
        "repositories" => [
          { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
        ]
      }
      config_path = create_test_config(config_data)
      config = described_class.new(config_path)

      settings = config.global_settings

      expect(settings["borg_path"]).to eq("/usr/local/bin/borg")
    end
  end

  describe "configuration validation" do
    describe "unknown key detection" do
      it "rejects unknown keys at global level" do
        config_data = {
          "unknown_option" => "value",
          "repositories" => [
            { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /unknown configuration key 'unknown_option'/)
      end

      it "rejects unknown keys at repository level" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "unknown_repo_option" => "value",
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /unknown configuration key 'unknown_repo_option'/)
      end

      it "allows unknown keys in borg_options (validated as warnings in CLI validate command)" do
        config_data = {
          "borg_options" => {
            "allow_relocated_repo" => true,
            "unknown_borg_option" => "value"
          },
          "repositories" => [
            { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
          ]
        }
        config_path = create_test_config(config_data)

        # Should not raise error - borg_options are validated as warnings in CLI validate command
        expect { described_class.new(config_path) }.not_to raise_error
      end

      it "rejects unknown keys in sources" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "sources" => [
                {
                  "name" => "s1",
                  "paths" => ["/p1"],
                  "unknown_source_key" => "value"
                }
              ]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /unknown configuration key 'unknown_source_key'/)
      end

      it "detects typos in common options" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "auto_prun" => true, # typo: should be auto_prune
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /unknown configuration key 'auto_prun'/)
      end
    end

    describe "retention policy validation" do
      it "validates retention policy with valid integer values" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "retention" => {
                "keep_daily" => 7,
                "keep_weekly" => 4,
                "keep_monthly" => 12
              },
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect { described_class.new(config_path) }.not_to raise_error
      end

      it "validates retention policy with valid time-based values" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "retention" => {
                "keep_within" => "7d",
                "keep_files_modified_within" => "30d"
              },
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect { described_class.new(config_path) }.not_to raise_error
      end

      it "rejects retention policy with string instead of integer" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "retention" => {
                "keep_daily" => "seven"
              },
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /must be a non-negative integer.*got String/)
      end

      it "rejects retention policy with negative integer" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "retention" => {
                "keep_daily" => -1
              },
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /must be a non-negative integer/)
      end

      it "rejects retention policy with invalid time format" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "retention" => {
                "keep_within" => "7days"
              },
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /invalid time format '7days'/)
      end

      it "rejects retention policy with integer instead of time string" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "retention" => {
                "keep_within" => 7
              },
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /must be a string \(e.g., '7d', '30d'\)/)
      end

      it "rejects unknown keys in retention policy" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "retention" => {
                "keep_daily" => 7,
                "unknown_retention_key" => "value"
              },
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /unknown configuration key 'unknown_retention_key'/)
      end

      it "rejects empty retention policy" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "retention" => {},
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /retention policy is empty/)
      end

      it "accepts valid time suffixes (h, d, w, m, y)" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "retention" => {
                "keep_within" => "24h"
              },
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect { described_class.new(config_path) }.not_to raise_error
      end

      it "validates retention_mode values" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "retention_mode" => "invalid_mode",
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /invalid value 'invalid_mode'.*Must be one of: standard, per_file/)
      end
    end

    describe "passbolt validation" do
      it "validates passbolt config with valid resource_id" do
        config_data = {
          "passbolt" => {
            "resource_id" => "valid-uuid-string"
          },
          "repositories" => [
            { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
          ]
        }
        config_path = create_test_config(config_data)

        expect { described_class.new(config_path) }.not_to raise_error
      end

      it "rejects passbolt config without resource_id" do
        config_data = {
          "passbolt" => {},
          "repositories" => [
            { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /missing required 'resource_id' key/)
      end

      it "rejects passbolt config with empty resource_id" do
        config_data = {
          "passbolt" => {
            "resource_id" => ""
          },
          "repositories" => [
            { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /resource_id: cannot be empty/)
      end

      it "rejects passbolt config with whitespace-only resource_id" do
        config_data = {
          "passbolt" => {
            "resource_id" => "   "
          },
          "repositories" => [
            { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /resource_id: cannot be empty/)
      end

      it "rejects passbolt config with non-string resource_id" do
        config_data = {
          "passbolt" => {
            "resource_id" => 123
          },
          "repositories" => [
            { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /resource_id: must be a string/)
      end

      it "rejects unknown keys in passbolt config" do
        config_data = {
          "passbolt" => {
            "resource_id" => "valid-uuid",
            "unknown_passbolt_key" => "value"
          },
          "repositories" => [
            { "name" => "repo1", "path" => "/path1", "sources" => [{ "name" => "s1", "paths" => ["/p1"] }] }
          ]
        }
        config_path = create_test_config(config_data)

        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError, /unknown configuration key 'unknown_passbolt_key'/)
      end

      it "validates passbolt at repository level" do
        config_data = {
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "passbolt" => {
                "resource_id" => "repo-specific-uuid"
              },
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        expect { described_class.new(config_path) }.not_to raise_error
      end
    end

    describe "multiple validation errors" do
      # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
      it "reports all validation errors at once" do
        config_data = {
          "unknown_global" => "value",
          "repositories" => [
            {
              "name" => "repo1",
              "path" => "/path1",
              "unknown_repo" => "value",
              "retention" => {
                "keep_daily" => "seven",
                "unknown_retention" => "value"
              },
              "passbolt" => {
                "resource_id" => ""
              },
              "sources" => [{ "name" => "s1", "paths" => ["/p1"] }]
            }
          ]
        }
        config_path = create_test_config(config_data)

        # rubocop:disable Style/MultilineBlockChain
        expect do
          described_class.new(config_path)
        end.to raise_error(Ruborg::ConfigError) do |error|
          expect(error.message).to include("unknown configuration key 'unknown_global'")
          expect(error.message).to include("unknown configuration key 'unknown_repo'")
          expect(error.message).to include("unknown configuration key 'unknown_retention'")
          expect(error.message).to include("must be a non-negative integer")
          expect(error.message).to include("resource_id: cannot be empty")
        end
        # rubocop:enable Style/MultilineBlockChain
      end
      # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
    end
  end
end
