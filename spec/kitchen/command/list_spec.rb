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

      # Stub a provisioner that does NOT have agentless support (standard).
      def stub_standard_provisioner(name = "ChefInfra")
        p = stub
        p.stubs(:name).returns(name)
        p.stubs(:respond_to?).with(:render_list_section).returns(false)
        p.stubs(:respond_to?).with(:render_pool_overflow_section).returns(false)
        p.stubs(:respond_to?).with(:agentless_node_status).returns(false)
        p
      end

      # Stub an agentless provisioner. render_list_section delegates to the shell
      # via KCAI; here we just stub it to be a no-op so we can verify it is called.
      def stub_agentless_provisioner(nodes, name = "ChefInfraAgentless")
        p = stub
        p.stubs(:name).returns(name)
        p.stubs(:respond_to?).with(:render_list_section).returns(true)
        p.stubs(:respond_to?).with(:render_pool_overflow_section).returns(true)
        p.stubs(:respond_to?).with(:agentless_node_status).returns(true)
        p.stubs(:agentless_node_status).returns(nodes)
        p.stubs(:render_list_section)
        p.stubs(:render_pool_overflow_section)
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
      # #list_remote_nodes — delegation to provisioner
      # ---------------------------------------------------------------------------

      describe "#list_remote_nodes" do
        it "outputs nothing when no instances use an agentless provisioner" do
          prov = stub_standard_provisioner
          instances = [stub_instance("default-ubuntu-2404", prov)]
          cmd, _shell = build_list_cmd(instances)
          prov.expects(:render_list_section).never
          cmd.send(:list_remote_nodes, instances)
        end

        it "calls render_list_section on each agentless provisioner" do
          nodes = [{ name: "edge1", node_id: "id1", mode: "container",
                     endpoint: "172.17.0.3:22", credentials: "Configured",
                     last_converge: "-", status: "Created" }]
          prov = stub_agentless_provisioner(nodes)
          instance = stub_instance("default-ubuntu-2404", prov)
          cmd, shell = build_list_cmd([instance])
          expected_map = { "id1" => "default-ubuntu-2404" }
          prov.expects(:render_list_section).with(shell, "default-ubuntu-2404", expected_map)
          cmd.send(:list_remote_nodes, [instance])
        end

        it "builds a first_seen map across instances and passes it to each provisioner" do
          node_id = "shared-node-id"
          nodes_a = [{ name: "n1", node_id: node_id, mode: "container",
                       endpoint: "-", credentials: "Container Key",
                       last_converge: "-", status: "<Not Created>" }]
          nodes_b = [{ name: "n1", node_id: node_id, mode: "container",
                       endpoint: "-", credentials: "Container Key",
                       last_converge: "-", status: "<Not Created>" }]
          prov_a = stub_agentless_provisioner(nodes_a)
          prov_b = stub_agentless_provisioner(nodes_b)
          inst_a = stub_instance("default-ubuntu-2404", prov_a)
          inst_b = stub_instance("default-almalinux-9", prov_b)
          cmd, shell = build_list_cmd([inst_a, inst_b])

          expected_map = { node_id => "default-ubuntu-2404" }
          prov_a.expects(:render_list_section).with(shell, "default-ubuntu-2404", expected_map)
          prov_b.expects(:render_list_section).with(shell, "default-almalinux-9", expected_map)

          cmd.send(:list_remote_nodes, [inst_a, inst_b])
        end

        it "skips standard instances — only calls render on agentless provisioners" do
          nodes = [{ name: "n1", node_id: "id1", mode: "container",
                     endpoint: "-", credentials: "Container Key",
                     last_converge: "-", status: "<Not Created>" }]
          std_prov = stub_standard_provisioner
          agl_prov = stub_agentless_provisioner(nodes)
          instances = [
            stub_instance("default-ubuntu-2404", std_prov),
            stub_instance("default-almalinux-9", agl_prov),
          ]
          cmd, shell = build_list_cmd(instances)
          expected_map = { "id1" => "default-almalinux-9" }
          std_prov.expects(:render_list_section).never
          agl_prov.expects(:render_list_section).with(shell, "default-almalinux-9", expected_map)
          cmd.send(:list_remote_nodes, instances)
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
                     credentials: "<None>", last_converge: "-", status: "<Not Created>" }]
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
