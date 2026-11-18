#
# Author:: Fletcher Nichol (<fnichol@nichol.ca>)
#
# Copyright (C) 2013, Chef Software Inc.
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

require "kitchen/command/destroy"

module Kitchen
  module Command
    describe Destroy do
      class InstanceStub
        attr_reader :destroyed, :cleaned_up

        def initialize
          @destroyed = false
          @cleaned_up = false
        end

        def destroy
          @destroyed = true
        end

        def cleanup!
          @cleaned_up = true
        end

        def name
          "default-ubuntu-2204"
        end
      end

      let(:instance) { InstanceStub.new }
      let(:config) { stub(instances: [instance]) }

      it "destroys instances via run_action" do
        command = Destroy.new(
          ["all"],
          {},
          config:,
          shell: Object.new,
          help: -> { nil },
          action: "destroy"
        )

        command.call

        _(instance.destroyed).must_equal true
        _(instance.cleaned_up).must_equal true
      end

      it "calls apply_driver_overrides before run_action" do
        overrides_applied = false
        # Prepend onto an isolated subclass (not the shared Destroy class
        # itself) so this override doesn't leak into other examples --
        # Ruby prepends are permanent for the lifetime of the process.
        subclass = Class.new(Destroy)
        subclass.prepend(Module.new do
          define_method(:apply_driver_overrides) do |_instances|
            overrides_applied = true
          end
        end)

        command = subclass.new(
          ["all"],
          {},
          config:,
          shell: Object.new,
          help: -> { nil },
          action: "destroy"
        )

        command.call

        _(overrides_applied).must_equal true
      end

      describe "--keep-agentless-source" do
        let(:driver_config) { {} }
        let(:driver) { stub(config: driver_config) }
        let(:instance_with_driver) { stub(name: "default-ubuntu-2204", driver:, destroy: nil, cleanup!: nil) }
        let(:config) { stub(instances: [instance_with_driver]) }

        it "passes keep_agentless_source through to the driver config" do
          command = Destroy.new(
            ["all"],
            { keep_agentless_source: true },
            config:,
            shell: Object.new,
            help: -> { nil },
            action: "destroy"
          )

          command.call

          _(driver_config[:keep_agentless_source]).must_equal true
        end

        it "does not set keep_agentless_source when the flag is omitted" do
          command = Destroy.new(
            ["all"],
            {},
            config:,
            shell: Object.new,
            help: -> { nil },
            action: "destroy"
          )

          command.call

          _(driver_config.key?(:keep_agentless_source)).must_equal false
        end
      end
    end
  end
end
