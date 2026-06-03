#
# Author:: Fletcher Nichol (<fnichol@nichol.ca>)
#
# Copyright:: (C) 2013, Fletcher Nichol
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

require_relative '../command'
require 'json' unless defined?(JSON)

module Kitchen
  module Command
    # Command to list one or more instances.
    #
    # @author Fletcher Nichol <fnichol@nichol.ca>
    class List < Kitchen::Command::Base
      # Invoke the command.
      def call
        result = parse_subcommand(args.first)
        if options[:debug]
          die 'The --debug flag on the list subcommand is deprecated, ' \
            "please use `kitchen diagnose'."
        elsif options[:bare]
          puts Array(result).map(&:name).join("\n")
        elsif options[:json]
          puts JSON.pretty_generate(Array(result).map { |r| to_hash(r) })
        else
          list_table(result)
          list_remote_nodes(result)
        end
      end

      private

      # Add a trailing ansi color escape code to line up columns of colored
      # output.
      #
      # @param string [String] a string
      # @return [String]
      # @api private
      def color_pad(string)
        string + colorize('', :white)
      end

      # Generate the display rows for an instance.
      #
      # @param instance [Instance] an instance
      # @return [Array<String>]
      # @api private
      def display_instance(instance)
        [
          color_pad(instance.name),
          color_pad(instance.driver.name),
          color_pad(instance.provisioner.name),
          color_pad(instance.verifier.name),
          color_pad(instance.transport.name),
          format_last_action(instance.last_action),
          format_last_error(instance.last_error),
        ]
      end

      # Format and color the given last action.
      #
      # @param last_action [String] the last action
      # @return [String] formatted last action
      # @api private
      def format_last_action(last_action)
        case last_action
        when 'create' then colorize('Created', :cyan)
        when 'converge' then colorize('Converged', :magenta)
        when 'setup' then colorize('Set Up', :blue)
        when 'verify' then colorize('Verified', :yellow)
        when nil then colorize('<Not Created>', :red)
        else colorize('<Unknown>', :white)
        end
      end

      # Format and color the given last error.
      #
      # @param last_error [String] the last error
      # @return [String] formatted last error
      # @api private
      def format_last_error(last_error)
        case last_error
        when nil then colorize('<None>', :white)
        else colorize(last_error, :red)
        end
      end

      # Constructs a list display table and output it to the screen.
      #
      # @param result [Array<Instance>] an array of instances
      # @api private
      def list_table(result)
        table = [
          [
            colorize('Instance', :green), colorize('Driver', :green),
            colorize('Provisioner', :green), colorize('Verifier', :green),
            colorize('Transport', :green), colorize('Last Action', :green),
            colorize('Last Error', :green)
          ],
        ]
        table += Array(result).map { |i| display_instance(i) }
        print_table(table)
      end

      # Constructs a hashtable representation of a single instance.
      #
      # @param result [Hash{Symbol => String}] hash of a single instance
      # @api private
      def to_hash(result)
        h = {
          instance: result.name,
          driver: result.driver.name,
          provisioner: result.provisioner.name,
          verifier: result.verifier.name,
          transport: result.transport.name,
          last_action: result.last_action,
          last_error: result.last_error,
        }
        if result.provisioner.respond_to?(:agentless_node_status)
          h[:remote_nodes] = result.provisioner.agentless_node_status
        end
        h
      end

      # Prints a "Remote Nodes" sub-table for each instance whose provisioner
      # supports {#agentless_node_status}.  Called after the main instance table.
      #
      # Outputs nothing if no instance is running in agentless mode or if all
      # provisioners return an empty node list.
      #
      # @param result [Array<Instance>] array of instances from parse_subcommand
      # @api private
      def list_remote_nodes(result)
        agentless_instances = Array(result).select do |i|
          i.provisioner.respond_to?(:agentless_node_status)
        end
        return if agentless_instances.empty?

        agentless_instances.each do |instance|
          nodes = instance.provisioner.agentless_node_status
          next if nodes.nil? || nodes.empty?

          puts ''
          puts colorize("Remote Nodes: #{instance.name}", :green)

          table = [[
            colorize('Node', :green),
            colorize('Mode', :green),
            colorize('Endpoint', :green),
            colorize('Credentials', :green),
            colorize('Status', :green),
            colorize('Last Converge', :green),
          ]]

          nodes.each do |n|
            table << [
              color_pad(n[:name].to_s),
              color_pad(n[:mode].to_s),
              color_pad(n[:endpoint].to_s),
              color_pad(n[:credentials_provisioned] ? 'Provisioned' : '<None>'),
              format_node_status(n[:status].to_s),
              color_pad(n[:last_converge].to_s),
            ]
          end

          print_table(table)
        end
      end

      # Format and color a remote node status string.
      #
      # @param status [String]
      # @return [String]
      # @api private
      def format_node_status(status)
        case status
        when 'Converged'     then colorize('Converged', :magenta)
        when 'Set Up'        then colorize('Set Up', :blue)
        when 'Created'       then colorize('Created', :cyan)
        when '<Not Created>' then colorize('<Not Created>', :red)
        else colorize(status, :white)
        end
      end

      # Outputs a formatted display table.
      #
      # @api private
      def print_table(*args)
        shell.print_table(*args)
      end

      # Colorize a string.
      #
      # @return [String] a colorized string
      # @api private
      def colorize(*args)
        shell.set_color(*args)
      end
    end
  end
end
