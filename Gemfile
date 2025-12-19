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
end

group :cookstyle do
  gem "cookstyle", ">= 8.2", "< 9.0"
end

group :build do
  gem "appbundler"
end

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
