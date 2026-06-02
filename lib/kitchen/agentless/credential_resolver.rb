# frozen_string_literal: true

#
# Author:: Test Kitchen Contributors
#
# Copyright:: Copyright (c) 2024 Chef Software Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "yaml" unless defined?(YAML)
require_relative "warnings"

module Kitchen
  module Agentless
    # Reads and validates a `credentials.yml` file, resolving credential entries
    # by node name. Raises appropriate warnings for insecure credential types.
    #
    # The `credentials.yml` schema:
    #
    #   remote-nodes:
    #     - name: <node-name>
    #       credential-source-type: inline | credential-file | databag
    #       transport: ssh | winrm
    #       # ... type-specific fields
    #
    # Out-of-scope types (`secret-service`, `service`, `env-vars`) raise a
    # {Kitchen::UserError} with a clear unsupported message.
    class CredentialResolver
      SUPPORTED_SOURCE_TYPES = %w{inline credential-file databag}.freeze
      UNSUPPORTED_SOURCE_TYPES = %w{secret-service service env-vars}.freeze
      VALID_TRANSPORTS = %w{ssh winrm}.freeze

      # @param credentials_yml_path [String] path to the credentials.yml file
      # @raise [Kitchen::UserError] if the file cannot be loaded or is malformed
      def initialize(credentials_yml_path)
        @credentials_yml_path = credentials_yml_path
        @entries = load_and_parse!
      end

      # Resolves the credential entry for a given node name.
      #
      # @param node_name [String] the name matching a `remote-nodes[].name` entry
      # @return [Hash] the credential entry hash
      # @raise [Kitchen::UserError] if no entry is found, source type is unsupported,
      #   or required fields are missing
      def resolve(node_name)
        entry = find_entry!(node_name)
        validate_entry!(entry)
        entry
      end

      # Returns all node names registered in the credentials file.
      #
      # @return [Array<String>]
      def registered_nodes
        @entries.map { |e| e["name"] }
      end

      private

      def load_and_parse!
        unless File.exist?(@credentials_yml_path)
          raise Kitchen::UserError,
            "Credentials file not found: #{@credentials_yml_path}"
        end

        data = YAML.load_file(@credentials_yml_path)

        unless data.is_a?(Hash) && data.key?("remote-nodes")
          raise Kitchen::UserError,
            "credentials.yml must contain a top-level 'remote-nodes' key (#{@credentials_yml_path})"
        end

        nodes = data["remote-nodes"]
        unless nodes.is_a?(Array)
          raise Kitchen::UserError,
            "credentials.yml 'remote-nodes' must be an Array (#{@credentials_yml_path})"
        end

        nodes
      end

      def find_entry!(node_name)
        entry = @entries.find { |e| e["name"] == node_name }
        return entry if entry

        raise Kitchen::UserError,
          "No credential entry found for node '#{node_name}' in #{@credentials_yml_path}. " \
          "Registered nodes: #{registered_nodes.join(", ")}"
      end

      def validate_entry!(entry)
        validate_source_type!(entry)
        validate_transport!(entry)
        validate_type_specific_fields!(entry)
      end

      def validate_source_type!(entry)
        source_type = entry["credential-source-type"]

        if source_type.nil?
          raise Kitchen::UserError,
            "Credential entry '#{entry["name"]}' is missing 'credential-source-type'"
        end

        if UNSUPPORTED_SOURCE_TYPES.include?(source_type)
          raise Kitchen::UserError,
            "Credential source type '#{source_type}' is not supported in this version of TKE. " \
            "Supported types: #{SUPPORTED_SOURCE_TYPES.join(", ")}"
        end

        return if SUPPORTED_SOURCE_TYPES.include?(source_type)

        raise Kitchen::UserError,
          "Unknown credential-source-type '#{source_type}' for node '#{entry["name"]}'. " \
          "Supported types: #{SUPPORTED_SOURCE_TYPES.join(", ")}"
      end

      def validate_transport!(entry)
        transport = entry["transport"]
        return if VALID_TRANSPORTS.include?(transport)

        raise Kitchen::UserError,
          "Credential entry '#{entry["name"]}' has invalid transport '#{transport}'. " \
          "Valid values: #{VALID_TRANSPORTS.join(", ")}"
      end

      def validate_type_specific_fields!(entry)
        case entry["credential-source-type"]
        when "inline"
          validate_inline!(entry)
        when "credential-file", "databag"
          validate_sourced!(entry)
        end
      end

      def validate_inline!(entry)
        if entry["transport"] == "ssh"
          missing = %w{ssh-user ssh-pass}.reject { |k| entry[k] }
          unless missing.empty?
            raise Kitchen::UserError,
              "Inline SSH credential entry '#{entry["name"]}' is missing: #{missing.join(", ")}"
          end
        elsif entry["transport"] == "winrm"
          missing = %w{winrm-user winrm-pass}.reject { |k| entry[k] }
          unless missing.empty?
            raise Kitchen::UserError,
              "Inline WinRM credential entry '#{entry["name"]}' is missing: #{missing.join(", ")}"
          end
        end
      end

      def validate_sourced!(entry)
        return unless entry["credential-source"].nil? || entry["credential-source"].to_s.empty?

        raise Kitchen::UserError,
          "Credential entry '#{entry["name"]}' (type: #{entry["credential-source-type"]}) " \
          "is missing required field 'credential-source'"
      end
    end
  end
end
