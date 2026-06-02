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

require_relative "remote_node"

module Kitchen
  module Agentless
    # Parses and validates the `agentless:` block from `kitchen.yml`, producing
    # a collection of {RemoteNode} objects.
    #
    # Supports two forms for `remote_nodes`:
    #   - **Array** (Pool Mode): nodes are assigned round-robin to Kitchen instances.
    #     Assignment strategy is implemented in CHEF-34610.
    #   - **Hash** (Explicit Mode): nodes keyed by instance name.
    #     Assignment strategy is implemented in CHEF-34610.
    #
    # This class is responsible for schema parsing and validation only.
    # Node assignment logic is deferred to CHEF-34610.
    class Context
      VALID_PARALLEL_MODES = %w{enabled disabled auto}.freeze

      attr_reader :parallel_mode, :remote_nodes, :assignment_form

      # Factory method — builds a Context from the raw `agentless:` config hash.
      #
      # @param config [Hash] the parsed `agentless:` block from kitchen.yml
      # @return [Kitchen::Agentless::Context]
      # @raise [Kitchen::UserError] if the config is nil, missing required keys,
      #   or contains invalid values
      def self.build(config)
        new(config).tap(&:validate!)
      end

      # @param config [Hash] the parsed `agentless:` block
      def initialize(config)
        @config = config || {}
        @parallel_mode  = (@config["parallel-mode"] || @config[:"parallel-mode"] || "disabled").to_s
        raw_nodes       = @config["remote_nodes"] || @config[:remote_nodes]
        @assignment_form, @remote_nodes = parse_remote_nodes(raw_nodes)
      end

      # @return [Boolean] true if remote_nodes was given as an Array (pool mode)
      def pool_mode?
        assignment_form == :pool
      end

      # @return [Boolean] true if remote_nodes was given as a Hash (explicit mode)
      def explicit_mode?
        assignment_form == :explicit
      end

      # Validates the entire agentless config, raising {Kitchen::UserError} on
      # any schema or field violation.
      #
      # @raise [Kitchen::UserError]
      def validate!
        validate_parallel_mode!
        validate_remote_nodes_present!
        remote_nodes.each(&:validate!)
      end

      private

      def parse_remote_nodes(raw)
        if raw.is_a?(Array)
          nodes = raw.map { |entry| RemoteNode.new(entry) }
          [:pool, nodes]
        elsif raw.is_a?(Hash)
          nodes = raw.map do |instance_name, entry|
            merged = (entry || {}).merge("name" => instance_name.to_s)
            RemoteNode.new(merged)
          end
          [:explicit, nodes]
        else
          [:pool, []]
        end
      end

      def validate_parallel_mode!
        return if VALID_PARALLEL_MODES.include?(parallel_mode)

        raise Kitchen::UserError,
          "agentless.parallel-mode '#{parallel_mode}' is invalid. " \
          "Valid values: #{VALID_PARALLEL_MODES.join(", ")}"
      end

      def validate_remote_nodes_present!
        return unless remote_nodes.empty?

        raise Kitchen::UserError,
          "agentless.remote_nodes must contain at least one node"
      end
    end
  end
end
