#
# Author:: GitHub Copilot (<support@github.com>)
#
# Copyright (C) 2026, Chef Software Inc.
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

require "kitchen/command/list"

module Kitchen
  module Command
    describe List do
      class FakeShell
        attr_reader :tables

        def initialize
          @tables = []
        end

        def print_table(table)
          @tables << table
        end

        def set_color(string, *_args)
          string
        end
      end

      let(:shell) { FakeShell.new }
      let(:driver) do
        stub(
          name: "agentless",
          source_info: {
            hostname: "source.example",
            port: 2200,
            driver: "docker",
            state: "running",
          }
        )
      end
      let(:command) do
        List.new(["all"], {}, config: stub(instances: [instance]), shell: shell, help: -> { nil })
      end
      let(:instance) do
        stub(
          name: "default-ubuntu-2204",
          driver: driver,
          provisioner: stub(name: "chef_zero"),
          verifier: stub(name: "inspec"),
          transport: stub(name: "ssh"),
          last_action: "create",
          last_error: nil
        )
      end

      it "does not render an Agentless Source section when no driver exposes source_info" do
        driver = stub(name: "dummy")
        instance = stub(
          name: "default-ubuntu-2204",
          driver:,
          provisioner: stub(name: "chef_zero"),
          verifier: stub(name: "inspec"),
          transport: stub(name: "ssh"),
          last_action: "create",
          last_error: nil
        )
        command = List.new(["all"], {}, config: stub(instances: [instance]), shell: shell, help: -> { nil })

        command.call

        _(shell.tables.length).must_equal 1
      end

      it "renders a single table when a driver provides source_info (source row handled by plugin)" do
        command.call

        # source_info rendering is delegated to kitchen-agentless via ListExtension.
        # When the plugin is not loaded, list_table produces exactly 1 table.
        _(shell.tables.length).must_equal 1
      end
    end
  end
end
