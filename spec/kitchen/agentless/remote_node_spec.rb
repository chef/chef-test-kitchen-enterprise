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
require "kitchen/agentless/remote_node"

describe Kitchen::Agentless::RemoteNode do
  def container_config(overrides = {})
    {
      "name" => "ecommerce1",
      "test-kitchen-mode" => "container",
      "test-kitchen-image" => "dokken/ubuntu-24.04",
      "credential-map-file" => "test/credentials.yml",
      "credential-passing-mode" => "pass-by-creds-file",
    }.merge(overrides)
  end

  def real_config(overrides = {})
    {
      "name" => "prod-node1",
      "test-kitchen-mode" => "real",
      "endpoint" => "192.168.1.100:22",
      "credential-map-file" => "test/credentials.yml",
      "credential-passing-mode" => "pass-cmd-line",
    }.merge(overrides)
  end

  describe "attribute readers" do
    let(:node) { Kitchen::Agentless::RemoteNode.new(container_config) }

    it "reads name" do
      _(node.name).must_equal "ecommerce1"
    end

    it "reads mode" do
      _(node.mode).must_equal "container"
    end

    it "reads image" do
      _(node.image).must_equal "dokken/ubuntu-24.04"
    end

    it "reads credential_map_file" do
      _(node.credential_map_file).must_equal "test/credentials.yml"
    end

    it "reads credential_passing_mode" do
      _(node.credential_passing_mode).must_equal "pass-by-creds-file"
    end

    it "reads optional fqdn as nil when not set" do
      _(node.fqdn).must_be_nil
    end

    it "reads optional compliance_mode_cred_file as nil when not set" do
      _(node.compliance_mode_cred_file).must_be_nil
    end
  end

  describe "#container_mode?" do
    it "returns true for container mode" do
      node = Kitchen::Agentless::RemoteNode.new(container_config)
      _(node.container_mode?).must_equal true
    end

    it "returns false for real mode" do
      node = Kitchen::Agentless::RemoteNode.new(real_config)
      _(node.container_mode?).must_equal false
    end
  end

  describe "#real_mode?" do
    it "returns true for real mode" do
      node = Kitchen::Agentless::RemoteNode.new(real_config)
      _(node.real_mode?).must_equal true
    end

    it "returns false for container mode" do
      node = Kitchen::Agentless::RemoteNode.new(container_config)
      _(node.real_mode?).must_equal false
    end
  end

  describe "#validate!" do
    describe "valid configs" do
      it "passes for a valid container node" do
        node = Kitchen::Agentless::RemoteNode.new(container_config)
        _(proc { node.validate! }).must_be_silent
      end

      it "passes for a valid real node" do
        node = Kitchen::Agentless::RemoteNode.new(real_config)
        _(proc { node.validate! }).must_be_silent
      end

      it "passes with optional fqdn set" do
        node = Kitchen::Agentless::RemoteNode.new(container_config("fqdn" => "host.myco.com"))
        _(proc { node.validate! }).must_be_silent
      end

      it "accepts all valid credential-passing-modes" do
        %w{pass-by-env-var pass-cmd-line pass-by-creds-file}.each do |mode|
          node = Kitchen::Agentless::RemoteNode.new(container_config("credential-passing-mode" => mode))
          _(proc { node.validate! }).must_be_silent
        end
      end
    end

    describe "missing name" do
      it "raises UserError when name is nil" do
        node = Kitchen::Agentless::RemoteNode.new(container_config("name" => nil))
        _(proc { node.validate! }).must_raise Kitchen::UserError
      end

      it "raises UserError when name is empty string" do
        node = Kitchen::Agentless::RemoteNode.new(container_config("name" => ""))
        _(proc { node.validate! }).must_raise Kitchen::UserError
      end
    end

    describe "invalid mode" do
      it "raises UserError for unknown mode" do
        node = Kitchen::Agentless::RemoteNode.new(container_config("test-kitchen-mode" => "virtual"))
        err = _(proc { node.validate! }).must_raise Kitchen::UserError
        _(err.message).must_include "virtual"
        _(err.message).must_include "container"
        _(err.message).must_include "real"
      end

      it "raises UserError when mode is nil" do
        node = Kitchen::Agentless::RemoteNode.new(container_config("test-kitchen-mode" => nil))
        _(proc { node.validate! }).must_raise Kitchen::UserError
      end
    end

    describe "container mode missing image" do
      it "raises UserError when test-kitchen-image is absent" do
        node = Kitchen::Agentless::RemoteNode.new(container_config("test-kitchen-image" => nil))
        err = _(proc { node.validate! }).must_raise Kitchen::UserError
        _(err.message).must_include "test-kitchen-image"
      end
    end

    describe "real mode missing endpoint" do
      it "raises UserError when endpoint is absent" do
        node = Kitchen::Agentless::RemoteNode.new(real_config("endpoint" => nil))
        err = _(proc { node.validate! }).must_raise Kitchen::UserError
        _(err.message).must_include "endpoint"
      end
    end

    describe "missing credential-map-file" do
      it "raises UserError" do
        node = Kitchen::Agentless::RemoteNode.new(container_config("credential-map-file" => nil))
        err = _(proc { node.validate! }).must_raise Kitchen::UserError
        _(err.message).must_include "credential-map-file"
      end
    end

    describe "invalid credential-passing-mode" do
      it "raises UserError for unknown mode" do
        node = Kitchen::Agentless::RemoteNode.new(container_config("credential-passing-mode" => "pass-by-magic"))
        err = _(proc { node.validate! }).must_raise Kitchen::UserError
        _(err.message).must_include "pass-by-magic"
      end
    end

    describe "symbol key support" do
      it "accepts symbol keys as well as string keys" do
        config = {
          name: "sym-node",
          "test-kitchen-mode": "container",
          "test-kitchen-image": "dokken/ubuntu-24.04",
          "credential-map-file": "test/creds.yml",
          "credential-passing-mode": "pass-by-creds-file",
        }
        node = Kitchen::Agentless::RemoteNode.new(config)
        _(proc { node.validate! }).must_be_silent
      end
    end

    describe "WinRM transport support" do
      let(:winrm_real_config) do
        {
          "name" => "win-server-1",
          "test-kitchen-mode" => "real",
          "transport" => "winrm",
          "endpoint" => "10.0.0.5:5985",
          "credential-map-file" => "test/creds.yml",
          "credential-passing-mode" => "pass-by-creds-file",
        }
      end

      it "accepts transport: winrm" do
        node = Kitchen::Agentless::RemoteNode.new(winrm_real_config)
        _(node.transport).must_equal "winrm"
        _(proc { node.validate! }).must_be_silent
      end

      it "winrm? returns true for transport: winrm" do
        node = Kitchen::Agentless::RemoteNode.new(winrm_real_config)
        _(node.winrm?).must_equal true
        _(node.ssh?).must_equal false
      end

      it "accepts transport: ssh explicitly" do
        config = winrm_real_config.merge("transport" => "ssh", "endpoint" => "10.0.0.5:22")
        node = Kitchen::Agentless::RemoteNode.new(config)
        _(node.transport).must_equal "ssh"
        _(node.ssh?).must_equal true
        _(node.winrm?).must_equal false
      end

      it "ssh? returns true when transport is not set" do
        config = winrm_real_config.reject { |k, _| k == "transport" }
        node = Kitchen::Agentless::RemoteNode.new(config)
        _(node.transport).must_be_nil
        _(node.ssh?).must_equal true
        _(node.winrm?).must_equal false
      end

      it "raises UserError for an invalid transport value" do
        config = winrm_real_config.merge("transport" => "rdp")
        node = Kitchen::Agentless::RemoteNode.new(config)
        err = _(proc { node.validate! }).must_raise Kitchen::UserError
        _(err.message).must_include "rdp"
        _(err.message).must_include "ssh"
        _(err.message).must_include "winrm"
      end

      it "accepts WinRM container-mode node" do
        config = {
          "name" => "win-ctr",
          "test-kitchen-mode" => "container",
          "transport" => "winrm",
          "test-kitchen-image" => "mcr.microsoft.com/windows/servercore:ltsc2022",
          "credential-map-file" => "test/creds.yml",
          "credential-passing-mode" => "pass-by-creds-file",
        }
        node = Kitchen::Agentless::RemoteNode.new(config)
        _(node.winrm?).must_equal true
        _(proc { node.validate! }).must_be_silent
      end
    end
  end
end
