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

require_relative '../../spec_helper'
require 'kitchen'
require 'kitchen/agentless/credential_resolver'
require 'tmpdir'
require 'yaml'

describe Kitchen::Agentless::CredentialResolver do
  # Write a credentials.yml to a temp file and return the path
  def write_credentials(data)
    file = Tempfile.new(['credentials', '.yml'])
    file.write(YAML.dump(data))
    file.flush
    file.path
  end

  def inline_ssh_entry(name: 'node1')
    { 'name' => name, 'credential-source-type' => 'inline', 'transport' => 'ssh',
      'ssh-user' => 'admin', 'ssh-pass' => 'secret' }
  end

  def cred_file_entry(name: 'node2')
    { 'name' => name, 'credential-source-type' => 'credential-file',
      'transport' => 'ssh', 'credential-source' => 'test/chef.toml' }
  end

  def databag_entry(name: 'node3')
    { 'name' => name, 'credential-source-type' => 'databag',
      'transport' => 'ssh', 'credential-source' => 'org1.databag2',
      'credential-name' => 'keys/my-node' }
  end

  def winrm_entry(name: 'win1')
    { 'name' => name, 'credential-source-type' => 'inline', 'transport' => 'winrm',
      'winrm-user' => 'Administrator', 'winrm-pass' => 'P@ssw0rd' }
  end

  describe '#initialize' do
    it 'raises UserError when file does not exist' do
      _(proc { Kitchen::Agentless::CredentialResolver.new('/nonexistent/creds.yml') })
        .must_raise Kitchen::UserError
    end

    it 'raises UserError when file has no remote-nodes key' do
      path = write_credentials({ 'nodes' => [] })
      _(proc { Kitchen::Agentless::CredentialResolver.new(path) })
        .must_raise Kitchen::UserError
    end

    it 'raises UserError when remote-nodes is not an Array' do
      path = write_credentials({ 'remote-nodes' => 'not-an-array' })
      _(proc { Kitchen::Agentless::CredentialResolver.new(path) })
        .must_raise Kitchen::UserError
    end

    it 'loads successfully with a valid credentials.yml' do
      path = write_credentials({ 'remote-nodes' => [inline_ssh_entry] })
      resolver = Kitchen::Agentless::CredentialResolver.new(path)
      _(resolver).must_be_kind_of Kitchen::Agentless::CredentialResolver
    end
  end

  describe '#registered_nodes' do
    it 'returns all node names' do
      path = write_credentials({ 'remote-nodes' => [inline_ssh_entry, cred_file_entry] })
      resolver = Kitchen::Agentless::CredentialResolver.new(path)
      _(resolver.registered_nodes).must_equal %w(node1 node2)
    end
  end

  describe '#resolve' do
    describe 'valid inline SSH entry' do
      it 'returns the credential entry hash' do
        path = write_credentials({ 'remote-nodes' => [inline_ssh_entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        entry = resolver.resolve('node1')
        _(entry['ssh-user']).must_equal 'admin'
        _(entry['ssh-pass']).must_equal 'secret'
      end
    end

    describe 'valid credential-file entry' do
      it 'returns the credential entry hash' do
        path = write_credentials({ 'remote-nodes' => [cred_file_entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        entry = resolver.resolve('node2')
        _(entry['credential-source']).must_equal 'test/chef.toml'
      end
    end

    describe 'valid databag entry' do
      it 'returns the credential entry hash' do
        path = write_credentials({ 'remote-nodes' => [databag_entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        entry = resolver.resolve('node3')
        _(entry['credential-source']).must_equal 'org1.databag2'
      end
    end

    describe 'valid WinRM inline entry' do
      it 'returns the credential entry hash' do
        path = write_credentials({ 'remote-nodes' => [winrm_entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        entry = resolver.resolve('win1')
        _(entry['winrm-user']).must_equal 'Administrator'
      end
    end

    describe 'node not found' do
      it 'raises UserError and lists registered nodes' do
        path = write_credentials({ 'remote-nodes' => [inline_ssh_entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        err = _(proc { resolver.resolve('nonexistent') }).must_raise Kitchen::UserError
        _(err.message).must_include 'nonexistent'
        _(err.message).must_include 'node1'
      end
    end

    describe 'unsupported credential-source-type' do
      %w(secret-service service env-vars).each do |unsupported|
        it "raises UserError for '#{unsupported}'" do
          entry = { 'name' => 'n1', 'credential-source-type' => unsupported,
                    'transport' => 'ssh' }
          path = write_credentials({ 'remote-nodes' => [entry] })
          resolver = Kitchen::Agentless::CredentialResolver.new(path)
          err = _(proc { resolver.resolve('n1') }).must_raise Kitchen::UserError
          _(err.message).must_include unsupported
        end
      end
    end

    describe 'unknown credential-source-type' do
      it 'raises UserError for completely unknown type' do
        entry = { 'name' => 'n1', 'credential-source-type' => 'magic-vault',
                  'transport' => 'ssh' }
        path = write_credentials({ 'remote-nodes' => [entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        err = _(proc { resolver.resolve('n1') }).must_raise Kitchen::UserError
        _(err.message).must_include 'magic-vault'
      end
    end

    describe 'missing credential-source-type' do
      it 'raises UserError' do
        entry = { 'name' => 'n1', 'transport' => 'ssh' }
        path = write_credentials({ 'remote-nodes' => [entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        _(proc { resolver.resolve('n1') }).must_raise Kitchen::UserError
      end
    end

    describe 'invalid transport' do
      it 'raises UserError for unknown transport' do
        entry = { 'name' => 'n1', 'credential-source-type' => 'inline',
                  'transport' => 'ftp', 'ssh-user' => 'u', 'ssh-pass' => 'p' }
        path = write_credentials({ 'remote-nodes' => [entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        err = _(proc { resolver.resolve('n1') }).must_raise Kitchen::UserError
        _(err.message).must_include 'ftp'
      end
    end

    describe 'inline SSH missing required fields' do
      it 'raises UserError when ssh-user is absent' do
        entry = inline_ssh_entry.reject { |k, _| k == 'ssh-user' }
        path = write_credentials({ 'remote-nodes' => [entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        err = _(proc { resolver.resolve('node1') }).must_raise Kitchen::UserError
        _(err.message).must_include 'ssh-user'
      end

      it 'raises UserError when ssh-pass is absent' do
        entry = inline_ssh_entry.reject { |k, _| k == 'ssh-pass' }
        path = write_credentials({ 'remote-nodes' => [entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        err = _(proc { resolver.resolve('node1') }).must_raise Kitchen::UserError
        _(err.message).must_include 'ssh-pass'
      end
    end

    describe 'inline WinRM missing required fields' do
      it 'raises UserError when winrm-pass is absent' do
        entry = winrm_entry.reject { |k, _| k == 'winrm-pass' }
        path = write_credentials({ 'remote-nodes' => [entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        err = _(proc { resolver.resolve('win1') }).must_raise Kitchen::UserError
        _(err.message).must_include 'winrm-pass'
      end
    end

    describe 'credential-file missing credential-source' do
      it 'raises UserError' do
        entry = { 'name' => 'n1', 'credential-source-type' => 'credential-file',
                  'transport' => 'ssh' }
        path = write_credentials({ 'remote-nodes' => [entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        err = _(proc { resolver.resolve('n1') }).must_raise Kitchen::UserError
        _(err.message).must_include 'credential-source'
      end
    end

    describe 'databag missing credential-source' do
      it 'raises UserError' do
        entry = { 'name' => 'n1', 'credential-source-type' => 'databag',
                  'transport' => 'ssh' }
        path = write_credentials({ 'remote-nodes' => [entry] })
        resolver = Kitchen::Agentless::CredentialResolver.new(path)
        err = _(proc { resolver.resolve('n1') }).must_raise Kitchen::UserError
        _(err.message).must_include 'credential-source'
      end
    end
  end
end
