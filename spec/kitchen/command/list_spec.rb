#
# Author:: Test Kitchen Contributors
#
# Copyright:: (C) 2024, Chef Software Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative "../../spec_helper"
require "kitchen"
require "kitchen/logging"
require "kitchen/command/list"

module Kitchen
  module Command
    # A real shell object that captures print_table calls and returns
    # the first argument as-is from set_color (no ANSI codes in tests).
    class TestShell
      attr_reader :table_calls, :put_lines

      def initialize
        @table_calls = []
        @put_lines   = []
      end

      def print_table(rows, *_opts)
        @table_calls << rows
      end

      # set_color returns the string unchanged so color_pad works correctly.
      def set_color(str, *_color)
        str.to_s
      end
    end

    describe List do
      # ---------------------------------------------------------------------------
      # Helpers
      # ---------------------------------------------------------------------------

      # Stub a provisioner that does NOT have agentless_node_status (standard).
      def stub_standard_provisioner(name = "ChefInfra")
        p = stub
        p.stubs(:name).returns(name)
        p.stubs(:respond_to?).with(:agentless_node_status).returns(false)
        p
      end

      # Stub an agentless provisioner with the given node list.
      def stub_agentless_provisioner(nodes, name = "ChefInfraAgentless")
        p = stub
        p.stubs(:name).returns(name)
        p.stubs(:respond_to?).with(:agentless_node_status).returns(true)
        p.stubs(:agentless_node_status).returns(nodes)
        p
      end

      # Stub a minimal instance.
      def stub_instance(name, provisioner, last_action: nil, last_error: nil)
        i = stub
        d = stub(name: "dokken")
        v = stub(name: "inspec")
        t = stub(name: "dokken")
        i.stubs(:name).returns(name)
        i.stubs(:driver).returns(d)
        i.stubs(:provisioner).returns(provisioner)
        i.stubs(:verifier).returns(v)
        i.stubs(:transport).returns(t)
        i.stubs(:last_action).returns(last_action)
        i.stubs(:last_error).returns(last_error)
        i
      end

      # Build a List command with a real TestShell that captures all output.
      # Returns [cmd, shell] so callers can inspect shell.table_calls.
      def build_list_cmd(instances, json: false, bare: false)
        shell = TestShell.new

        cmd = List.allocate
        cmd.instance_variable_set(:@args, ["all"])
        cmd.instance_variable_set(:@options, { json: json, bare: bare, debug: false })
        cmd.instance_variable_set(:@shell, shell)

        # Stub parse_subcommand to return our test instances
        cmd.stubs(:parse_subcommand).returns(instances)
        [cmd, shell]
      end

      # ---------------------------------------------------------------------------
      # #list_remote_nodes — display path
      # ---------------------------------------------------------------------------

      describe "#list_remote_nodes" do
        it "outputs nothing when no instances use an agentless provisioner" do
          prov = stub_standard_provisioner
          instances = [stub_instance("default-ubuntu-2404", prov)]
          cmd, shell = build_list_cmd(instances)
          cmd.send(:list_remote_nodes, instances)
          _(shell.table_calls).must_be_empty
        end

        it "outputs nothing when the agentless provisioner returns an empty array" do
          prov = stub_agentless_provisioner([])
          instances = [stub_instance("default-ubuntu-2404", prov)]
          cmd, shell = build_list_cmd(instances)
          cmd.send(:list_remote_nodes, instances)
          _(shell.table_calls).must_be_empty
        end

        it "calls print_table once for an agentless instance with nodes" do
          nodes = [
            {
              name: "edge1", mode: "container", endpoint: "172.17.0.3:22",
              credentials_provisioned: true, last_converge: "-", status: "Set Up"
            },
          ]
          prov = stub_agentless_provisioner(nodes)
          instance = stub_instance("default-ubuntu-2404", prov)
          cmd, shell = build_list_cmd([instance])
          cmd.send(:list_remote_nodes, [instance])
          # One print_table call for the one agentless instance
          _(shell.table_calls.size).must_equal 1
        end

        it "prints a table with one data row per remote node (plus a header row)" do
          nodes = [
            {
              name: "node-a", mode: "real", endpoint: "10.0.0.1:22",
              credentials_provisioned: false, last_converge: "-", status: "Created"
            },
            {
              name: "node-b", mode: "container", endpoint: "172.17.0.4:22",
              credentials_provisioned: true, last_converge: "2026-01-01T00:00:00Z", status: "Converged"
            },
          ]
          prov = stub_agentless_provisioner(nodes)
          instance = stub_instance("default-ubuntu-2404", prov)
          cmd, shell = build_list_cmd([instance])
          cmd.send(:list_remote_nodes, [instance])

          # 1 header row + 2 data rows
          rows = shell.table_calls.first
          _(rows.size).must_equal 3
          # Node names appear in data rows
          data_rows = rows.drop(1)
          _(data_rows.any? { |r| r.first.to_s.include?("node-a") }).must_equal true
          _(data_rows.any? { |r| r.first.to_s.include?("node-b") }).must_equal true
        end

        it "shows 'Provisioned' in the credentials column when credentials_provisioned is true" do
          nodes = [
            {
              name: "n1", mode: "real", endpoint: "10.0.0.1:22",
              credentials_provisioned: true, last_converge: "-", status: "Set Up"
            },
          ]
          prov = stub_agentless_provisioner(nodes)
          instance = stub_instance("default-ubuntu-2404", prov)
          cmd, shell = build_list_cmd([instance])
          cmd.send(:list_remote_nodes, [instance])

          data_row = shell.table_calls.first[1] # first data row (after header)
          _(data_row.any? { |c| c.to_s.include?("Provisioned") }).must_equal true
        end

        it "shows '<None>' in the credentials column when credentials_provisioned is false" do
          nodes = [
            {
              name: "n1", mode: "real", endpoint: "10.0.0.1:22",
              credentials_provisioned: false, last_converge: "-", status: "Created"
            },
          ]
          prov = stub_agentless_provisioner(nodes)
          instance = stub_instance("default-ubuntu-2404", prov)
          cmd, shell = build_list_cmd([instance])
          cmd.send(:list_remote_nodes, [instance])

          data_row = shell.table_calls.first[1]
          _(data_row.any? { |c| c.to_s.include?("<None>") }).must_equal true
        end

        it "calls print_table once per agentless instance with nodes" do
          nodes1 = [{ name: "n1", mode: "container", endpoint: "172.17.0.2:22",
                      credentials_provisioned: true, last_converge: "-", status: "Set Up" }]
          nodes2 = [{ name: "n2", mode: "real", endpoint: "10.0.0.2:22",
                      credentials_provisioned: false, last_converge: "-", status: "<Not Created>" }]
          instances = [
            stub_instance("default-ubuntu-2404", stub_agentless_provisioner(nodes1)),
            stub_instance("default-almalinux-9", stub_agentless_provisioner(nodes2)),
          ]
          cmd, shell = build_list_cmd(instances)
          cmd.send(:list_remote_nodes, instances)
          _(shell.table_calls.size).must_equal 2
        end

        it "skips standard instances — only prints tables for agentless ones" do
          agentless_nodes = [{ name: "n1", mode: "container", endpoint: "-",
                               credentials_provisioned: false, last_converge: "-", status: "<Not Created>" }]
          instances = [
            stub_instance("default-ubuntu-2404", stub_standard_provisioner),
            stub_instance("default-almalinux-9", stub_agentless_provisioner(agentless_nodes)),
          ]
          cmd, shell = build_list_cmd(instances)
          cmd.send(:list_remote_nodes, instances)
          # Only one print_table call (for the agentless instance)
          _(shell.table_calls.size).must_equal 1
        end
      end

      # ---------------------------------------------------------------------------
      # #format_node_status
      # ---------------------------------------------------------------------------

      describe "#format_node_status" do
        let(:cmd) do
          c = List.allocate
          c.instance_variable_set(:@shell, TestShell.new)
          c
        end

        it "returns 'Converged' for Converged status" do
          _(cmd.send(:format_node_status, "Converged")).must_equal "Converged"
        end

        it "returns 'Set Up' for Set Up status" do
          _(cmd.send(:format_node_status, "Set Up")).must_equal "Set Up"
        end

        it "returns 'Created' for Created status" do
          _(cmd.send(:format_node_status, "Created")).must_equal "Created"
        end

        it "returns '<Not Created>' for <Not Created> status" do
          _(cmd.send(:format_node_status, "<Not Created>")).must_equal "<Not Created>"
        end

        it "returns the raw string for an unknown status" do
          _(cmd.send(:format_node_status, "SomethingElse")).must_equal "SomethingElse"
        end
      end

      # ---------------------------------------------------------------------------
      # #to_hash — JSON output
      # ---------------------------------------------------------------------------

      describe "#to_hash" do
        let(:cmd) do
          c = List.allocate
          c.instance_variable_set(:@shell, TestShell.new)
          c
        end

        it "does not include remote_nodes for a standard provisioner" do
          prov = stub_standard_provisioner
          instance = stub_instance("default-ubuntu-2404", prov, last_action: "converge")
          h = cmd.send(:to_hash, instance)
          _(h.key?(:remote_nodes)).must_equal false
        end

        it "includes remote_nodes for an agentless provisioner" do
          nodes = [{ name: "n1", mode: "container", endpoint: "-",
                     credentials_provisioned: false, last_converge: "-", status: "<Not Created>" }]
          prov = stub_agentless_provisioner(nodes)
          instance = stub_instance("default-ubuntu-2404", prov, last_action: "converge")
          h = cmd.send(:to_hash, instance)
          _(h.key?(:remote_nodes)).must_equal true
          _(h[:remote_nodes]).must_equal nodes
        end

        it "includes standard fields for all instances" do
          prov = stub_standard_provisioner
          instance = stub_instance("default-ubuntu-2404", prov, last_action: "create")
          h = cmd.send(:to_hash, instance)
          _(h[:instance]).must_equal "default-ubuntu-2404"
          _(h[:driver]).must_equal "dokken"
          _(h[:provisioner]).must_equal "ChefInfra"
          _(h[:last_action]).must_equal "create"
        end
      end
    end
  end
end
