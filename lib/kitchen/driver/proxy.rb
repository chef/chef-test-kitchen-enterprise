#
# Author:: Seth Chisamore <schisamo@opscode.com>
#
# Copyright:: Copyright (c) 2013 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require_relative "base"
require_relative "../version"

module Kitchen
  module Driver
    # Simple driver that proxies commands through to a test instance whose
    # lifecycle is not managed by Test Kitchen. This driver is useful for long-
    # lived non-ephemeral test instances that are simply "reset" between test
    # runs. Think executing against devices like network switches--this is why
    # the driver was created.
    #
    # @author Seth Chisamore <schisamo@opscode.com>
    class Proxy < Kitchen::Driver::Base
      include ShellOut
      include Configurable
      include Logging

      plugin_version Kitchen::VERSION

      required_config :host
      default_config :reset_command, nil

      no_parallel_for :create, :destroy

      # Creates a new Driver object using the provided configuration data
      # which will be merged with any default configuration.
      #
      # @param config [Hash] provided driver configuration
      def initialize(config = {})
        init_config(config)
      end

      # (see Base#create)
      def create(state)
        super
        state[:hostname] = config[:host]
        reset_instance(state)
      end

      # (see Base#converge)
      def converge(state) # rubocop:disable Metrics/AbcSize
        provisioner = instance.provisioner
        provisioner.create_sandbox
        sandbox_dirs = provisioner.sandbox_dirs

        instance.transport.connection(state) do |conn|
          conn.execute(env_cmd(provisioner.install_command))
          conn.execute(env_cmd(provisioner.init_command))
          info("Transferring files to #{instance.to_str}")
          conn.upload(sandbox_dirs, provisioner[:root_path])
          info("Transfer complete")
          conn.execute(env_cmd(provisioner.prepare_command))
          conn.execute(env_cmd(provisioner.run_command))
          info("Downloading files from #{instance.to_str}")
          provisioner[:downloads].to_h.each do |remotes, local|
            debug("Downloading #{Array(remotes).join(", ")} to #{local}")
            conn.download(remotes, local)
          end
          debug("Download complete")
        end
      rescue Kitchen::Transport::TransportFailed => ex
        raise ActionFailed, ex.message
      ensure
        instance.provisioner.cleanup_sandbox
      end

      # (see Base#setup)
      def setup(state)
        verifier = instance.verifier

        instance.transport.connection(state) do |conn|
          conn.execute(env_cmd(verifier.install_command))
        end
      rescue Kitchen::Transport::TransportFailed => ex
        raise ActionFailed, ex.message
      end

      # (see Base#verify)
      def verify(state) # rubocop:disable Metrics/AbcSize
        verifier = instance.verifier
        verifier.create_sandbox
        sandbox_dirs = Util.list_directory(verifier.sandbox_path)

        instance.transport.connection(state) do |conn|
          conn.execute(env_cmd(verifier.init_command))
          info("Transferring files to #{instance.to_str}")
          conn.upload(sandbox_dirs, verifier[:root_path])
          debug("Transfer complete")
          conn.execute(env_cmd(verifier.prepare_command))
          conn.execute(env_cmd(verifier.run_command))
        end
      rescue Kitchen::Transport::TransportFailed => ex
        raise ActionFailed, ex.message
      ensure
        instance.verifier.cleanup_sandbox
      end

      # (see Base#destroy)
      def destroy(state)
        return if state[:hostname].nil?

        reset_instance(state)
        state.delete(:hostname)
      end

      private

      # Resets the non-Kitchen managed instance using by issuing a command
      # over SSH.
      #
      # @param state [Hash] the state hash
      # @api private
      def reset_instance(state)
        if (cmd = config[:reset_command])
          info("Resetting instance state with command: #{cmd}")
          instance.transport.connection(state) do |conn|
            conn.execute(env_cmd(command))
          end
        end
      end

      # Adds http, https and ftp proxy environment variables to a command, if
      # set in configuration data or on local workstation.
      #
      # @param cmd [String] command string
      # @return [String] command string
      # @api private
      # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity, Metrics/AbcSize
      def env_cmd(cmd)
        return if cmd.nil?

        env = String.new("env")
        http_proxy = config[:http_proxy] || ENV["http_proxy"] ||
                     ENV["HTTP_PROXY"]
        https_proxy = config[:https_proxy] || ENV["https_proxy"] ||
                      ENV["HTTPS_PROXY"]
        ftp_proxy = config[:ftp_proxy] || ENV["ftp_proxy"] ||
                    ENV["FTP_PROXY"]
        no_proxy = if (!config[:http_proxy] && http_proxy) ||
                      (!config[:https_proxy] && https_proxy) ||
                      (!config[:ftp_proxy] && ftp_proxy)
                     ENV["no_proxy"] || ENV["NO_PROXY"]
                   end
        env << " http_proxy=#{http_proxy}"   if http_proxy
        env << " https_proxy=#{https_proxy}" if https_proxy
        env << " ftp_proxy=#{ftp_proxy}"     if ftp_proxy
        env << " no_proxy=#{no_proxy}"       if no_proxy

        env == "env" ? cmd : "#{env} #{cmd}"
      end
    end
  end
end
