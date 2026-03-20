source "https://rubygems.org"

gemspec name: 'chef-test-kitchen-enterprise'
gemspec name: 'test-kitchen' # Alias gemspec to satisfy transitive dependencies on test-kitchen

# net-ssh 7.3.1 has a regression in Net::SSH::Test::Extensions::PacketStream#idle!
# where StringIO#string= resets pos to 0 before self.pos = pos can restore it,
# causing the ssh_spec wait loop to spin forever. Exclude until upstream fixes it.
gem "net-ssh", "!= 7.3.1"

# Windows-specific gems for the chef-tke habitat pkg
if RUBY_PLATFORM.match?(/mswin|mingw|windows/)
  gem "win32-security"
  gem "win32-process"
end

group :integration do
  gem "chef-cli", ">= 6.1.27"
  gem "berkshelf", ">=8.1.21"
  gem "kitchen-vagrant", ">= 2.2.1"
  gem "kitchen-dokken", ">= 2.22.2", git: "https://github.com/chef/kitchen-dokken", branch: "main"
  gem "kitchen-inspec", ">= 3.1" # Ensure support for latest TK 4.x
  gem "kitchen-ec2", ">= 3.22.1"
  gem "kitchen-google", ">= 2.6.2"
  gem "kitchen-azurerm", ">= 1.13.6"
  gem "kitchen-hyperv", ">= 0.10.3"
  gem "kitchen-vcenter", ">= 2.12.3"
  gem "chef", ">= 19.1" # Chef-CLI depends on chef. This ensures we are getting a newer version
  # Check if Artifactory is accessible, otherwise use GitHub
  artifactory_url = "https://artifactory-internal.ps.chef.co/artifactory/api/gems/omnibus-gems-local"
  artifactory_available = begin
                            require "net/http"
                            require "uri"
                            uri = URI.parse(artifactory_url)
                            http = Net::HTTP.new(uri.host, uri.port)
                            http.use_ssl = true
                            http.open_timeout = 3
                            http.read_timeout = 3
                            response = http.head(uri.path)
                            response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
                          rescue StandardError
                            false
                          end

  if artifactory_available
    source artifactory_url do
      gem "kitchen-chef-enterprise", ">= 1.2.3"
    end
  else
    gem "kitchen-chef-enterprise", ">= 1.2.3", git: "https://github.com/chef/kitchen-chef-enterprise", branch: "main"
  end
  gem "rake" # needed for windows
end

group :cookstyle do
  gem "cookstyle", ">= 8.2", "< 9.0"
end

group :test do
  gem "rb-readline"
  gem "aruba",     ">= 0.11", "< 3.0"
  gem "countloc",  ">= 0.4", "< 1.0"
  gem "cucumber",  ">= 9.2", "< 11"
  gem "fakefs",    ">= 3.0", "< 4.0"
  gem "maruku",    ">= 0.7", "< 1.0"
  gem "minitest",  ">= 5.3", "< 7.0"
  gem "mocha",     ">= 2.0", "< 4.0"
  gem "irb"
end
