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

module Kitchen
  module Agentless
    # OWASP-compliant security warning messages for insecure credential handling.
    # Warnings are issued at runtime but do not block execution.
    module Warnings
      # Warning issued when credentials are stored as plaintext inline in credentials.yml.
      # Corresponds to OWASP A02:2021 - Cryptographic Failures.
      INLINE_PLAINTEXT_WARNING = <<~MSG
        [TKE SECURITY WARNING] Plaintext credentials detected in credentials.yml.
        Storing SSH/WinRM passwords in plaintext violates OWASP A02:2021 (Cryptographic Failures).
        Recommendation: Use 'credential-file' with passphrase encryption instead.
        See: https://owasp.org/Top10/A02_2021-Cryptographic_Failures/
      MSG

      # Warning issued when credentials are passed via command-line arguments,
      # which may be visible in process listings.
      CMDLINE_PASSING_WARNING = <<~MSG
        [TKE SECURITY WARNING] Credentials are being passed via command-line arguments.
        Command-line arguments may be visible to other users via process listings (e.g., ps aux).
        This violates OWASP A02:2021 (Cryptographic Failures) by exposing secrets in process state.
        Recommendation: Use 'pass-by-creds-file' to reduce credential exposure.
        See: https://owasp.org/Top10/A02_2021-Cryptographic_Failures/
      MSG

      # Warning issued when credentials are passed via environment variables.
      ENVVAR_PASSING_WARNING = <<~MSG
        [TKE SECURITY WARNING] Credentials are being passed via environment variables.
        Environment variables may be leaked via /proc, debug output, or child processes.
        This violates OWASP A02:2021 (Cryptographic Failures) by exposing secrets in the process environment.
        Recommendation: Use 'pass-by-creds-file' to reduce credential exposure.
        See: https://owasp.org/Top10/A02_2021-Cryptographic_Failures/
      MSG
    end
  end
end
