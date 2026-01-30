#
# Author:: Fletcher Nichol (<fnichol@nichol.ca>)
#
# Copyright (C) 2012, Fletcher Nichol
# Copyright (C) 2018, Chef Software
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

require_relative "errors"
require_relative "util"
require "kitchen/licensing/config" unless defined?(Kitchen::Licensing)

module Kitchen
  module Plugin
    # Returns an instance of a plugin given a type, name, and config.
    #
    # @param type [Module] a Kitchen::<Module> of one of the plugin types
    #   (Driver, Provisioner, Transport, Verifier)
    # @param plugin [String] a plugin name, which will be constantized
    # @param config [Hash] a configuration hash to initialize the plugin
    # @return [Kitchen::<Module>::Base] a plugin instance
    # @raise [ClientError] if a plugin instance could not be created
    # @raise [UserError] if the plugin's dependencies could not be met
    def self.load(type, plugin, config)
      type_name = Kitchen::Util.snake_case(type.name.split("::").last)

      # Pre-activate all kitchen-* gems before attempting to load plugins.
      # This is critical for plugins whose gem names don't match their require paths
      # (e.g., kitchen-chef-enterprise provides kitchen/provisioner/chef_infra).
      # Without pre-activation, RubyGems can't auto-discover these gems when require is called.
      activate_kitchen_gems
      first_load = require("kitchen/#{type_name}/#{plugin}")

      str_const = Kitchen::Util.camel_case(plugin)
      klass = type.const_get(str_const)
      object = klass.new(config)
      object.verify_dependencies if first_load
      object
    rescue UserError
      raise
    rescue NameError => e
      raise ClientError, "Could not load the '#{plugin}' #{type_name}. Error: #{e.message}"
    rescue LoadError => e
      available_plugins = plugins_available(type_name)
      error_message = if available_plugins.include?(plugin)
                        e.message
                      else
                        " Did you mean: #{available_plugins.join(", ")} ?" \
                        " Please ensure that your #{type_name} is installed as a gem or included" \
                        " in your Gemfile if using Bundler."
                      end
      raise ClientError, "Could not load the '#{plugin}' #{type_name} from the load path." + error_message
    ensure
      # If any of the plugins has a different licensing configuration, after loading it,
      # it might override the kitchen licensing configuration. To fix this issue we will reconfigure it again.
      if ChefLicensing::Config.chef_entitlement_id != Kitchen::Licensing::ENTITLEMENT_ID
        Kitchen::Licensing.configure_licensing
      end
    end

    # given a type of plugin, searches the Ruby load path for plugins of that
    # type based on the path+naming convention that plugin loading is based upon
    #
    # @param plugin_type [String] the name of a plugin type (e.g. driver,
    #   provisioner, transport, verifier)
    # @return [Array<String>] a collection of Ruby filenames that are probably
    #   plugins of the given type
    def self.plugins_available(plugin_type)
      $LOAD_PATH.map { |load_path| Dir[File.expand_path("kitchen/#{plugin_type}/*.rb", load_path)] }
        .reject(&:empty?)
        .flatten
        .uniq
        .select { |plugin_path| File.readlines(plugin_path).grep(/^\s*class \w* </).any? }
        .map { |plugin_path| File.basename(plugin_path).gsub(/\.rb$/, "") }
        .reject { |plugin_name| plugin_name == "base" }
        .sort
    end

    # Activate all kitchen-* plugin gems to ensure they're in the load path.
    #
    # Background: RubyGems normally auto-activates gems when you require a file,
    # but only if it can discover which gem provides that file. This works when
    # the gem name matches the require path (e.g., kitchen-ec2 provides kitchen/driver/ec2).
    #
    # Problem: Some gems have mismatched names and require paths:
    # - kitchen-chef-enterprise provides kitchen/provisioner/chef_infra
    # - RubyGems searches for a gem named "kitchen-provisioner-chef-infra" (doesn't exist)
    # - Result: LoadError even though the gem is installed
    #
    # Solution: Pre-activate all kitchen-* gems by explicitly calling `gem 'name', 'version'`
    # before any plugin loading. This adds their lib directories to $LOAD_PATH so subsequent
    # require calls work regardless of name/path mismatches.
    #
    # @api private
    def self.activate_kitchen_gems
      return if @kitchen_gems_activated

      gem_home = ENV["GEM_HOME"]
      return unless gem_home && Dir.exist?(File.join(gem_home, "gems"))

      # Scan gem_path for all kitchen-* plugin gems
      Dir[File.join(gem_home, "gems", "kitchen-*")].each do |gem_path|
        gem_name_version = File.basename(gem_path)
        # Extract gem name and version from directory name (e.g., kitchen-ec2-3.21.0)
        next unless gem_name_version =~ /^(.+)-(\d+\.\d+\.\d+.*?)$/

        gem_name = $1
        gem_version = $2
        begin
          # Activate gem: adds its lib/ directory to $LOAD_PATH
          gem gem_name, gem_version
        rescue Gem::LoadError
          # Gem activation failed (wrong version, missing dependencies, etc.) - skip it
        end
      end

      @kitchen_gems_activated = true
    end
  end
end
