export HAB_BLDR_CHANNEL="base-2025"
export HAB_REFRESH_CHANNEL="base-2025"
pkg_name="chef-test-kitchen-enterprise"
pkg_origin="chef"
pkg_maintainer="The Chef Maintainers <humans@chef.io>"
pkg_description="The Chef Test Kitchen Enterprise"
pkg_license=('Apache-2.0')
_chef_client_ruby="core/ruby3_4"
pkg_bin_dirs=(
  bin
)
pkg_build_deps=(
  core/make
  core/bash
  core/gcc
)
pkg_deps=(
  ${_chef_client_ruby}
  core/coreutils
  core/git
)
pkg_svc_user=root

pkg_version() {
  cat "$SRC_PATH/VERSION"
}

do_before() {
  update_pkg_version
}

do_setup_environment() {
  build_line 'Setting GEM_HOME="$pkg_prefix/vendor"'
  export GEM_HOME="$pkg_prefix/vendor"

  build_line "Setting GEM_PATH=$GEM_HOME"
  export GEM_PATH="$GEM_HOME"
}

do_unpack() {
  mkdir -pv "$HAB_CACHE_SRC_PATH/$pkg_dirname"
  cp -RT "$PLAN_CONTEXT"/.. "$HAB_CACHE_SRC_PATH/$pkg_dirname/"
}

do_build() {
  export GEM_HOME="$pkg_prefix/vendor"

  build_line "Setting GEM_PATH=$GEM_HOME"
  export GEM_PATH="$GEM_HOME"
  export CHEF_TEST_KITCHEN_ENTERPRISE="true"
  bundle config --local without deploy maintenance
  bundle config --local with integration habitat
  bundle config --local jobs 4
  bundle config --local retry 5
  bundle config --local silence_root_warning 1

  bundle install
  ruby ./post-bundle-install.rb

  gem build chef-test-kitchen-enterprise.gemspec
  gem build test-kitchen.gemspec
}

do_install() {
  export GEM_HOME="$pkg_prefix/vendor"

  build_line "Setting GEM_PATH=$GEM_HOME"
  export GEM_PATH="$GEM_HOME"
  cleanup_community_test_kitchen_gem

  gem install "chef-test-kitchen-enterprise-$(pkg_version).gem" --no-document --force --ignore-dependencies
  gem install test-kitchen-*.gem --no-document --force --ignore-dependencies

  make_pkg_official_distrib

  wrap_ruby_kitchen
  set_runtime_env "GEM_PATH" "${pkg_prefix}/vendor"
}

wrap_ruby_kitchen() {
  local bin="$pkg_prefix/bin/kitchen"
  local real_bin="$GEM_HOME/gems/chef-test-kitchen-enterprise-$(pkg_version)/bin/kitchen"
  wrap_bin_with_ruby "$bin" "$real_bin"
}

wrap_bin_with_ruby() {
  local bin="$1"
  local real_bin="$2"
  local ruby_default_gem_dir

  # Include the packaged Ruby's default gem directory in GEM_PATH.
  ruby_default_gem_dir="$(env -u GEM_HOME -u GEM_PATH "$(pkg_path_for $_chef_client_ruby)/bin/ruby" -rrubygems -e 'puts Gem.default_dir')"
  build_line "Detected Ruby default gem dir: ${ruby_default_gem_dir}"

  build_line "Adding wrapper $bin to $real_bin"
  cat <<EOF > "$bin"
#!$(pkg_path_for core/bash)/bin/bash
set -e

# Set binary path that allows chef-test-kitchen-enterprise to use non-Hab pkg binaries
export PATH="/sbin:/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin:\$PATH"

# Set Ruby paths defined from 'do_setup_environment()'
export GEM_HOME="$pkg_prefix/vendor"
export GEM_PATH="\$GEM_HOME:${ruby_default_gem_dir}"

# Set encoding to UTF-8 to handle non-ASCII characters in gem files
export RUBYOPT="-Eutf-8"

exec $(pkg_path_for $_chef_client_ruby)/bin/ruby $real_bin \$@
EOF
  chmod -v 755 "$bin"
}

make_pkg_official_distrib() {
  # Install chef-official-distribution without dependencies since bundler already installed everything
  build_line "Installing chef-official-distribution gem (package-level only)"
  gem source --add "https://artifactory-internal.ps.chef.co/artifactory/omnibus-gems-local/"
  gem install chef-official-distribution --no-document --install-dir "$GEM_HOME" --ignore-dependencies
  gem sources -r "https://artifactory-internal.ps.chef.co/artifactory/omnibus-gems-local/"
}

do_strip() {
  return 0
}

# Some kitchen-plugins may install the community test-kitchen gem as a dependency.
# This can cause conflicts with the alias gem we are using from chef-test-kitchen-enterprise.
# This function checks for the presence of the community test-kitchen gem and removes it if found
cleanup_community_test_kitchen_gem() {
  # Check if community test-kitchen gem is installed and remove it to avoid conflicts
  if gem list -i "^test-kitchen$" > /dev/null 2>&1; then
    build_line "Removing community test-kitchen gem to avoid conflicts with alias gem"
    gem uninstall test-kitchen --all --ignore-dependencies --executables || true
  fi
}
