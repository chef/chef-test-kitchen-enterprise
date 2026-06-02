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

require_relative "../../spec_helper"
require "kitchen/agentless/warnings"

describe Kitchen::Agentless::Warnings do
  it "defines INLINE_PLAINTEXT_WARNING with OWASP reference" do
    _(Kitchen::Agentless::Warnings::INLINE_PLAINTEXT_WARNING).must_include "OWASP"
    _(Kitchen::Agentless::Warnings::INLINE_PLAINTEXT_WARNING).must_include "plaintext"
  end

  it "defines CMDLINE_PASSING_WARNING with OWASP reference" do
    _(Kitchen::Agentless::Warnings::CMDLINE_PASSING_WARNING).must_include "OWASP"
    _(Kitchen::Agentless::Warnings::CMDLINE_PASSING_WARNING).must_include "command-line"
  end

  it "defines ENVVAR_PASSING_WARNING with OWASP reference" do
    _(Kitchen::Agentless::Warnings::ENVVAR_PASSING_WARNING).must_include "OWASP"
    _(Kitchen::Agentless::Warnings::ENVVAR_PASSING_WARNING).must_include "environment"
  end

  it "all warning constants are frozen strings" do
    _(Kitchen::Agentless::Warnings::INLINE_PLAINTEXT_WARNING).must_be :frozen?
    _(Kitchen::Agentless::Warnings::CMDLINE_PASSING_WARNING).must_be :frozen?
    _(Kitchen::Agentless::Warnings::ENVVAR_PASSING_WARNING).must_be :frozen?
  end
end
