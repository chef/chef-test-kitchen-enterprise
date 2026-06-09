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

require_relative "warnings"

module Kitchen
  module Agentless
    # Immutable value object representing a single remote (target) node
    # as configured in the `agentless.remote_nodes` section of `kitchen.yml`.
    #
    # A RemoteNode can operate in two modes:
    #   - `:container` — TKE spins up a Docker container as the target
    #   - `:real`      — TKE connects to a pre-existing node via SSH/WinRM
    class RemoteNode
      VALID_MODES = %w{container real}.freeze
      VALID_CREDENTIAL_PASSING_MODES = %w{pass-by-env-var pass-cmd-line pass-by-creds-file}.freeze
      VALID_TRANSPORTS = %w{ssh winrm}.freeze

      # Default ports for each transport protocol (used for validation hints).
      WINRM_DEFAULT_PORT = 5985
      SSH_DEFAULT_PORT   = 22

      attr_reader :name, :node_id, :assignment_key, :mode, :image, :fqdn, :endpoint,
        :credential_map_file, :credential_passing_mode,
        :compliance_mode_cred_file, :transport

      # @param config [Hash] a single entry from the remote_nodes Array
      # @raise [Kitchen::UserError] if required fields are missing or invalid
      def initialize(config)
        @name                    = config["name"] || config[:name]
        # node_id uniquely identifies this node in state files and logs.
        # For single-node explicit entries it equals name; for multi-node
        # explicit entries (Array value) it is "<instance_key>[<index>]".
        @node_id                 = config["node_id"] || config[:node_id] || @name
        # assignment_key is the kitchen instance name used for explicit lookup.
        # Equals name for single-node entries; equals the instance key for
        # multi-node entries where name may differ from the instance key.
        @assignment_key          = config["assignment_key"] || config[:assignment_key] || @name
        @mode                    = config["test-kitchen-mode"] || config[:"test-kitchen-mode"]
        @image                   = config["test-kitchen-image"] || config[:"test-kitchen-image"]
        @fqdn                    = config["fqdn"] || config[:fqdn]
        @endpoint                = config["endpoint"] || config[:endpoint]
        @credential_map_file     = config["credential-map-file"] || config[:"credential-map-file"]
        @credential_passing_mode = config["credential-passing-mode"] || config[:"credential-passing-mode"]
        @compliance_mode_cred_file = config["compliance-mode-cred-file"] || config[:"compliance-mode-cred-file"]
        @transport = (config["transport"] || config[:transport])&.to_s
      end

      # @return [Boolean] true if this node is managed as a Docker container
      def container_mode?
        mode == "container"
      end

      # @return [Boolean] true if this node is a pre-existing real machine
      def real_mode?
        mode == "real"
      end

      # @return [Boolean] true if the transport for this node is WinRM.
      # When `transport` is not explicitly set, the transport is determined
      # by the credentials file; this returns false in that case.
      def winrm?
        transport == "winrm"
      end

      # @return [Boolean] true if the transport for this node is SSH (or unset).
      def ssh?
        transport.nil? || transport == "ssh"
      end

      # Validates that all required fields are present and values are legal.
      #
      # @raise [Kitchen::UserError] with a descriptive message on failure
      def validate!
        raise Kitchen::UserError, "Remote node is missing required field 'name'" if name.nil? || name.empty?

        validate_mode!
        validate_transport!
        validate_container_fields! if container_mode?
        validate_real_fields! if real_mode?
        validate_credential_fields!
      end

      private

      def validate_transport!
        return if transport.nil?
        return if VALID_TRANSPORTS.include?(transport)

        raise Kitchen::UserError,
          "Remote node '#{name}' has invalid transport '#{transport}'. " \
          "Valid values: #{VALID_TRANSPORTS.join(", ")}"
      end

      def validate_mode!
        return if VALID_MODES.include?(mode)

        raise Kitchen::UserError,
          "Remote node '#{name}' has invalid test-kitchen-mode '#{mode}'. " \
          "Valid values: #{VALID_MODES.join(", ")}"
      end

      def validate_container_fields!
        return unless image.nil? || image.empty?

        raise Kitchen::UserError,
          "Remote node '#{name}' is in container mode but is missing 'test-kitchen-image'"
      end

      def validate_real_fields!
        return unless endpoint.nil? || endpoint.empty?

        raise Kitchen::UserError,
          "Remote node '#{name}' is in real mode but is missing 'endpoint' (expected format: host:port)"
      end

      def validate_credential_fields!
        # Container mode uses docker:// transport — no credentials needed.
        # credential-map-file and credential-passing-mode are ignored for
        # container nodes.
        return if container_mode?

        if credential_map_file.nil? || credential_map_file.empty?
          raise Kitchen::UserError,
            "Remote node '#{name}' is missing required field 'credential-map-file'"
        end

        return if VALID_CREDENTIAL_PASSING_MODES.include?(credential_passing_mode)

        raise Kitchen::UserError,
          "Remote node '#{name}' has invalid credential-passing-mode '#{credential_passing_mode}'. " \
          "Valid values: #{VALID_CREDENTIAL_PASSING_MODES.join(", ")}"
      end
    end
  end
end
