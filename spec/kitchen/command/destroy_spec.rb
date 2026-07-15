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

require "kitchen/command/destroy"

module Kitchen
  module Command
    describe Destroy do
      class DriverConfigStub
        def initialize
          @config = {}
        end

        private

        attr_reader :config
      end

      class InstanceStub
        attr_reader :driver, :destroyed, :cleaned_up

        def initialize(driver)
          @driver = driver
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

      let(:driver) { DriverConfigStub.new }
      let(:instance) { InstanceStub.new(driver) }
      let(:config) { stub(instances: [instance]) }

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

        _(instance.destroyed).must_equal true
        _(instance.cleaned_up).must_equal true
        _(driver.send(:config)[:keep_agentless_source]).must_equal true
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

        _(driver.send(:config).key?(:keep_agentless_source)).must_equal false
      end
    end
  end
end
