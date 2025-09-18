source "https://rubygems.org"

gemspec
gem "appbundler"
gem "pry"
gem "mutex_m"
gem "benchmark"
gem "kitchen-dokken", git: "https://github.com/chef/kitchen-dokken", branch: "main"
gem "kitchen-inspec", git: "https://github.com/inspec/kitchen-inspec", branch: "temp-point-to-chef-test-kitchen-ent"
# Use chef-licensing branch that contains require_license_for method
gem "chef-licensing", github: "chef/chef-licensing", branch: "nm/introducing-optional-mode", glob: "components/ruby/chef-licensing.gemspec"
group :test do
  gem "rake"
  gem "rb-readline"
  gem "aruba",     ">= 0.11", "< 3.0"
  gem "countloc",  "~> 0.4"
  gem "cucumber",  ">= 9.2", "< 10"
  gem "fakefs",    "~> 3.0"
  gem "maruku",    "~> 0.6"
  gem "minitest",  "~> 5.3", "< 6.0"
  gem "mocha",     "~> 2.0"
end

group :integration do
  gem "chef-cli"
  gem "kitchen-vagrant"
end

group :chefstyle do
  gem "chefstyle", "2.2.3"
end
# gem "chef-test-kitchen-enterprise"
