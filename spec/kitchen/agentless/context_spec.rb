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
require "kitchen"
require "kitchen/agentless/context"
require "tmpdir"

describe Kitchen::Agentless::Context do
  def base_node_config
    {
      "name" => "ecommerce1",
      "test-kitchen-mode" => "container",
      "test-kitchen-image" => "dokken/ubuntu-24.04",
      "credential-map-file" => "test/credentials.yml",
      "credential-passing-mode" => "pass-by-creds-file",
    }
  end

  def real_node_config
    {
      "name" => "prod-node",
      "test-kitchen-mode" => "real",
      "endpoint" => "10.0.0.1:22",
      "credential-map-file" => "test/credentials.yml",
      "credential-passing-mode" => "pass-cmd-line",
    }
  end

  describe ".build" do
    it "returns a Context instance" do
      config = { "parallel-mode" => "disabled", "remote_nodes" => [base_node_config] }
      ctx = Kitchen::Agentless::Context.build(config)
      _(ctx).must_be_kind_of Kitchen::Agentless::Context
    end

    it "raises UserError when config is empty and remote_nodes is missing" do
      _(proc { Kitchen::Agentless::Context.build({}) }).must_raise Kitchen::UserError
    end
  end

  describe "#parallel_mode" do
    it "defaults to 'disabled' when not set" do
      config = { "remote_nodes" => [base_node_config] }
      ctx = Kitchen::Agentless::Context.new(config)
      _(ctx.parallel_mode).must_equal "disabled"
    end

    it "reads 'enabled'" do
      config = { "parallel-mode" => "enabled", "remote_nodes" => [base_node_config] }
      ctx = Kitchen::Agentless::Context.new(config)
      _(ctx.parallel_mode).must_equal "enabled"
    end

    it "reads 'auto'" do
      config = { "parallel-mode" => "auto", "remote_nodes" => [base_node_config] }
      ctx = Kitchen::Agentless::Context.new(config)
      _(ctx.parallel_mode).must_equal "auto"
    end
  end

  describe "pool mode (Array remote_nodes)" do
    let(:config) { { "remote_nodes" => [base_node_config, real_node_config] } }
    let(:ctx)    { Kitchen::Agentless::Context.new(config) }

    it "sets assignment_form to :pool" do
      _(ctx.assignment_form).must_equal :pool
    end

    it "pool_mode? returns true" do
      _(ctx.pool_mode?).must_equal true
    end

    it "explicit_mode? returns false" do
      _(ctx.explicit_mode?).must_equal false
    end

    it "creates RemoteNode objects for each entry" do
      _(ctx.remote_nodes.length).must_equal 2
      _(ctx.remote_nodes.first).must_be_kind_of Kitchen::Agentless::RemoteNode
    end

    it "preserves node names" do
      names = ctx.remote_nodes.map(&:name)
      _(names).must_include "ecommerce1"
      _(names).must_include "prod-node"
    end
  end

  describe "explicit mode (Hash remote_nodes)" do
    let(:config) do
      {
        "remote_nodes" => {
          "default-ubuntu-24.04" => {
            "test-kitchen-mode" => "container",
            "test-kitchen-image" => "dokken/ubuntu-24.04",
            "credential-map-file" => "test/credentials.yml",
            "credential-passing-mode" => "pass-by-creds-file",
          },
        },
      }
    end
    let(:ctx) { Kitchen::Agentless::Context.new(config) }

    it "sets assignment_form to :explicit" do
      _(ctx.assignment_form).must_equal :explicit
    end

    it "pool_mode? returns false" do
      _(ctx.pool_mode?).must_equal false
    end

    it "explicit_mode? returns true" do
      _(ctx.explicit_mode?).must_equal true
    end

    it "uses the hash key as the node name" do
      _(ctx.remote_nodes.first.name).must_equal "default-ubuntu-24.04"
    end
  end

  describe "#validate!" do
    it "passes for valid pool config" do
      config = { "remote_nodes" => [base_node_config] }
      ctx = Kitchen::Agentless::Context.new(config)
      _(proc { ctx.validate! }).must_be_silent
    end

    it "raises UserError for invalid parallel-mode" do
      config = { "parallel-mode" => "turbo", "remote_nodes" => [base_node_config] }
      ctx = Kitchen::Agentless::Context.new(config)
      err = _(proc { ctx.validate! }).must_raise Kitchen::UserError
      _(err.message).must_include "turbo"
    end

    it "raises UserError when remote_nodes is empty" do
      config = { "remote_nodes" => [] }
      ctx = Kitchen::Agentless::Context.new(config)
      err = _(proc { ctx.validate! }).must_raise Kitchen::UserError
      _(err.message).must_match(/remote_nodes must contain at least one node/)
    end

    it "raises UserError when remote_nodes is absent" do
      ctx = Kitchen::Agentless::Context.new({})
      _(proc { ctx.validate! }).must_raise Kitchen::UserError
    end

    it "mentions ERB templating in the empty remote_nodes error message" do
      config = { "remote_nodes" => [] }
      ctx = Kitchen::Agentless::Context.new(config)
      err = _(proc { ctx.validate! }).must_raise Kitchen::UserError
      _(err.message).must_match(/ERB/)
    end

    it "propagates UserError from invalid RemoteNode" do
      bad_node = base_node_config.merge("test-kitchen-mode" => "invalid")
      config = { "remote_nodes" => [bad_node] }
      ctx = Kitchen::Agentless::Context.new(config)
      _(proc { ctx.validate! }).must_raise Kitchen::UserError
    end

    it "accepts all valid parallel-mode values" do
      %w{enabled disabled auto}.each do |mode|
        config = { "parallel-mode" => mode, "remote_nodes" => [base_node_config] }
        ctx = Kitchen::Agentless::Context.new(config)
        _(proc { ctx.validate! }).must_be_silent
      end
    end
  end

  describe "nil config" do
    it "initializes safely when config is nil" do
      ctx = Kitchen::Agentless::Context.new(nil)
      _(ctx.parallel_mode).must_equal "disabled"
      _(ctx.remote_nodes).must_be_empty
    end
  end
end
