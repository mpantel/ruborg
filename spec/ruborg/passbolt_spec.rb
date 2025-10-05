# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ruborg::Passbolt do
  let(:resource_id) { "test-uuid-1234" }

  describe "#initialize" do
    it "accepts a resource_id parameter" do
      passbolt = described_class.new(resource_id: resource_id)

      expect(passbolt.instance_variable_get(:@resource_id)).to eq(resource_id)
    end

    it "checks for passbolt CLI availability" do
      expect_any_instance_of(described_class).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)

      described_class.new(resource_id: resource_id)
    end

    it "raises error if passbolt CLI is not installed" do
      allow_any_instance_of(described_class).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(false)

      expect {
        described_class.new(resource_id: resource_id)
      }.to raise_error(Ruborg::PassboltError, /Passbolt CLI not found/)
    end
  end

  describe "#get_password" do
    let(:passbolt) { described_class.new(resource_id: resource_id) }

    before do
      allow_any_instance_of(described_class).to receive(:system).with("which passbolt > /dev/null 2>&1").and_return(true)
    end

    it "raises error if resource_id is not configured" do
      passbolt_without_id = described_class.new(resource_id: nil)

      expect {
        passbolt_without_id.get_password
      }.to raise_error(Ruborg::PassboltError, /Resource ID not configured/)
    end

    it "executes passbolt get resource command with correct parameters" do
      json_response = '{"password": "secret-password"}'
      allow(passbolt).to receive(:execute_command).and_return([json_response, true])

      password = passbolt.get_password

      expect(password).to eq("secret-password")
    end

    it "parses password field from JSON response" do
      json_response = '{"password": "my-secret", "other": "data"}'
      allow(passbolt).to receive(:execute_command).and_return([json_response, true])

      password = passbolt.get_password

      expect(password).to eq("my-secret")
    end

    it "falls back to secret field if password is not present" do
      json_response = '{"secret": "my-secret"}'
      allow(passbolt).to receive(:execute_command).and_return([json_response, true])

      password = passbolt.get_password

      expect(password).to eq("my-secret")
    end

    it "raises error when passbolt command fails" do
      allow(passbolt).to receive(:execute_command).and_return(["", false])

      expect {
        passbolt.get_password
      }.to raise_error(Ruborg::PassboltError, /Failed to retrieve password/)
    end

    it "raises error when JSON parsing fails" do
      invalid_json = "not valid json"
      allow(passbolt).to receive(:execute_command).and_return([invalid_json, true])

      expect {
        passbolt.get_password
      }.to raise_error(Ruborg::PassboltError, /Failed to parse Passbolt response/)
    end
  end
end