source "https://rubygems.org"

gemspec name: 'chef-test-kitchen-enterprise'

group :test do
  gem "rake"
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

group :integration do
  gem "chef-cli"
  gem "kitchen-dokken", git: "https://github.com/chef/kitchen-dokken", branch: "main"
  gem "kitchen-inspec"
  gem "inspec-core", ">= 5.0", "< 6.6.0" # Inspec 6.6.0+ requires license key to run, this limits it to pre license key for CI and testing purposes
  # Override transitive dependency on test-kitchen with chef-test-kitchen-enterprise
  # The git repo now includes a test-kitchen.gemspec alias to satisfy transitive dependencies
  gem "test-kitchen", git: "https://github.com/chef/chef-test-kitchen-enterprise", branch: "main", glob: "test-kitchen.gemspec" # TODO: update branch to main once PR is merged https://github.com/chef/chef-test-kitchen-enterprise/pull/60
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
      gem "kitchen-chef-enterprise"
    end
  else
    gem "kitchen-chef-enterprise", git: "https://github.com/chef/kitchen-chef-enterprise", branch: "main"
  end
end

group :cookstyle do
  gem "cookstyle", ">= 8.2", "< 9.0"
end

group :build do
  gem "appbundler"
end
