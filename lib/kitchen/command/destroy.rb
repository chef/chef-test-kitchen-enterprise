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

require_relative "action"

module Kitchen
  module Command
    # Command to destroy one or more instances.
    class Destroy < Action
      # Invoke the command.
      def call
        banner "Starting Chef Test Kitchen Enterprise (v#{Kitchen::VERSION})"
        elapsed = Benchmark.measure do
          results = parse_subcommand(args.first)
          apply_driver_overrides(Array(results))
          run_action(action, results)
        end
        banner "Chef Test Kitchen Enterprise is finished. #{Util.duration(elapsed.real)}"
      end

      private

      def apply_driver_overrides(instances)
        return unless options[:keep_agentless_source]

        instances.each do |instance|
          instance.driver.send(:config)[:keep_agentless_source] = true
        end
      end
    end
  end
end
