source "https://rubygems.org"

gemspec name: 'chef-test-kitchen-enterprise'

group :test do
  gem "rake"
  gem "rb-readline"
  gem "aruba",     ">= 0.11", "< 3.0"
  gem "countloc",  "~> 0.4"
  gem "cucumber",  ">= 9.2", "< 11"
  gem "fakefs",    "~> 3.0"
  gem "maruku",    "~> 0.7"
  gem "minitest",  "~> 5.3", "< 6.0"
  gem "mocha",     "~> 2.0"
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

source "https://artifactory-internal.ps.chef.co/artifactory/api/gems/omnibus-gems-local" do
  gem "kitchen-chef-enterprise"
end
