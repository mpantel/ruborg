# frozen_string_literal: true

require "json"

module Ruborg
  # Passbolt CLI integration for password management
  class Passbolt
    def initialize(resource_id: nil)
      @resource_id = resource_id
      check_passbolt_cli
    end

    def get_password
      raise PassboltError, "Resource ID not configured" unless @resource_id

      cmd = ["passbolt", "get", "resource", @resource_id, "--json"]
      output, status = execute_command(cmd)

      raise PassboltError, "Failed to retrieve password from Passbolt" unless status

      parse_password(output)
    end

    private

    def check_passbolt_cli
      return if system("which passbolt > /dev/null 2>&1")

      raise PassboltError, "Passbolt CLI not found. Please install it first."
    end

    def execute_command(cmd)
      require "open3"
      stdout, _, status = Open3.capture3(*cmd)
      [stdout, status.success?]
    end

    def parse_password(json_output)
      data = JSON.parse(json_output)
      data["password"] || data["secret"]
    rescue JSON::ParserError => e
      raise PassboltError, "Failed to parse Passbolt response: #{e.message}"
    end
  end
end
