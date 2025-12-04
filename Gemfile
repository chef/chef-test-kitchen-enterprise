source "https://rubygems.org"

gemspec

gem "chef-licensing", git: "https://github.com/chef/chef-licensing", branch: "Stromweld-patch-1", glob: "components/ruby/*.gemspec" # TODO: remove once PR is merged https://github.com/chef/chef-licensing/pull/215

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
  gem "kitchen-chef-enterprise", git: "https://github.com/chef/kitchen-chef-enterprise", branch: "new-gem" # TODO: update this when the new gem is released
  gem "kitchen-dokken", git: "https://github.com/chef/kitchen-dokken", branch: "main"
  gem "kitchen-inspec", git: "https://github.com/inspec/kitchen-inspec", branch: "temp-point-to-chef-test-kitchen-ent_a"
  gem "kitchen-vagrant", ">= 2.1.2"
end

group :cookstyle do
  gem "cookstyle", "~> 8.2"
end

group :build do
  gem "appbundler"
end

