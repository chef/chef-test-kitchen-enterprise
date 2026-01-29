lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "kitchen/version"

Gem::Specification.new do |gem|
  gem.name          = "test-kitchen"
  gem.version       = "4.999.0" # Higher version number than community test-kitchen
  gem.license       = "Apache-2.0"
  gem.authors       = ["Fletcher Nichol"]
  gem.email         = ["fnichol@nichol.ca"]
  gem.description   = "Alias gem for chef-test-kitchen-enterprise. " \
                      "Test Kitchen is an integration tool for developing " \
                      "and testing infrastructure code and software on " \
                      "isolated target platforms."
  gem.summary       = "Alias gem for chef-test-kitchen-enterprise"
  gem.homepage      = "https://kitchen.ci/"

  # This is a shim/alias gem that simply depends on chef-test-kitchen-enterprise
  # This allows other gems with transitive dependencies on test-kitchen to use
  # chef-test-kitchen-enterprise as a drop-in replacement
  gem.files         = %w{LICENSE test-kitchen.gemspec}
  gem.executables   = []
  gem.require_paths = ["lib"]

  gem.required_ruby_version = ">= 3.1"

  # The only dependency is the real implementation
  gem.add_dependency "chef-test-kitchen-enterprise", ">= #{Kitchen::VERSION}"

  gem.post_install_message = <<~MESSAGE

    ═══════════════════════════════════════════════════════════════════════════
    Thank you for installing test-kitchen!

    This is an alias gem that installs chef-test-kitchen-enterprise.
    All functionality is provided by chef-test-kitchen-enterprise.
    ═══════════════════════════════════════════════════════════════════════════

  MESSAGE
end
