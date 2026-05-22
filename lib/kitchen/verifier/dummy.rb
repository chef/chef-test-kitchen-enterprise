#
# Author:: Fletcher Nichol (<fnichol@nichol.ca>)
#
# Copyright (C) 2015, Fletcher Nichol
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

require_relative "base"

module Kitchen
  module Verifier
    # Dummy verifier for Kitchen. This verifier does nothing but report what
    # would happen if this verifier did anything of consequence. As a result
    # it may be a useful verifier to use when debugging or developing new
    # features or plugins.
    #
    # @author Fletcher Nichol <fnichol@nichol.ca>
    class Dummy < Kitchen::Verifier::Base
      kitchen_verifier_api_version 1

      plugin_version Kitchen::VERSION

      default_config :sleep, 0
      default_config :random_failure, false

      # (see Base#call)
      def call(state)
        validate_state!(state)
        info("[#{name}] Verify on instance=#{instance} with state=#{state}")
        sleep_if_set
        failure_if_set
        debug("[#{name}] Verify completed (#{config[:sleep]}s).")
      end

      private

      # Sleep for a period of time, if a value is set in the config.
      #
      # @api private
      def sleep_if_set
        sleep(config[:sleep].to_f) if config[:sleep].to_f > 0.0
      end

      # Simulate a failure in an action, if set in the config.
      # Priority is explicit failure (`:fail`) over random failure.
      #
      # @api private
      def failure_if_set
        if config[:fail]
          debug("Failure for Verifier #{name}.")
          fail_verify!
        elsif config[:random_failure] && randomly_fail?
          debug("Random failure for Verifier #{name}.")
          fail_verify!
        end
      end

      # Ensure the public call boundary receives the expected state type.
      #
      # @param state [Hash]
      # @raise [ArgumentError]
      # @api private
      def validate_state!(state)
        return if state.is_a?(Hash)

        raise ArgumentError, "state must be a Hash"
      end

      # Raise a verify-specific ActionFailed with a stable message.
      #
      # @raise [ActionFailed]
      # @api private
      def fail_verify!
        raise ActionFailed, "Action #verify failed for #{instance.to_str}."
      end

      # Determine whether or not to randomly fail.
      #
      # @return [true, false]
      # @api private
      def randomly_fail?
        [true, false].sample
      end
    end
  end
end
