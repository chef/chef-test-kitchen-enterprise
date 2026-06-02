export HAB_BLDR_CHANNEL="base-2025"
export HAB_REFRESH_CHANNEL="base-2025"
pkg_name="chef-test-kitchen-enterprise"
pkg_origin="chef"
pkg_maintainer="The Chef Maintainers <humans@chef.io>"
pkg_description="The Chef Test Kitchen Enterprise"
pkg_license=('Apache-2.0')
_ruby_pkg="core/ruby3_4"
pkg_bin_dirs=(
  bin
)
pkg_build_deps=(
  core/make
  core/bash
  core/sed
  core/gcc
  core/git
)
pkg_deps=(
  ${_ruby_pkg}
  core/coreutils
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
  bundle config --local without "deploy maintenance test cookstyle"
  bundle config --local jobs 4
  bundle config --local retry 5
  bundle config --local silence_root_warning 1

  bundle install
  # appbundler requires Gemfile.lock in BUNDLE_DIR. Generate it only when missing
  # so this stays aligned with chef pattern if a lockfile is later committed.
  if [[ ! -f Gemfile.lock ]]; then
    bundle lock
  fi
  ruby ./cleanup_lint_roller.rb
  ruby ./post-bundle-install.rb

  gem build chef-test-kitchen-enterprise.gemspec
  gem build test-kitchen.gemspec
}

do_install() {

  # Copy NOTICE.TXT to the package directory
  if [[ -f "$PLAN_CONTEXT/../NOTICE" ]]; then
    build_line "Copying NOTICE to package directory"
    cp "$PLAN_CONTEXT/../NOTICE" "$pkg_prefix/"
  else
    build_line "Warning: NOTICE not found at $PLAN_CONTEXT/../NOTICE"
  fi

  export GEM_HOME="$pkg_prefix/vendor"

  build_line "Setting GEM_PATH=$GEM_HOME"
  export GEM_PATH="$GEM_HOME"
  cleanup_community_test_kitchen_gem

  gem install "chef-test-kitchen-enterprise-$(pkg_version).gem" --no-document --force --ignore-dependencies
  gem install test-kitchen-*.gem --no-document --force --ignore-dependencies

  make_pkg_official_distrib

  build_line "Generating appbundler binstubs with precise version pins"
  "$(pkg_path_for $_ruby_pkg)/bin/ruby" "$pkg_prefix/vendor/bin/appbundler" "$HAB_CACHE_SRC_PATH/$pkg_dirname" "$pkg_prefix/bin" "chef-test-kitchen-enterprise"

  build_line "Patching generated binstubs for Habitat runtime env"
  for binstub in "$pkg_prefix"/bin/*; do
    if [[ -f "$binstub" ]]; then
      sed -i "/require \"rubygems\"/r $PLAN_CONTEXT/binstub_patch.rb" "$binstub"
    fi
  done

  set_runtime_env "GEM_PATH" "${pkg_prefix}/vendor"
  set_runtime_env "APPBUNDLER_ALLOW_RVM" "true"
}

make_pkg_official_distrib() {
  # Install chef-official-distribution without dependencies since bundler already installed everything
  build_line "Installing chef-official-distribution gem (package-level only)"
  gem source --add "https://artifactory-internal.ps.chef.co/artifactory/omnibus-gems-local/"
  gem install chef-official-distribution --no-document --install-dir "$GEM_HOME" --ignore-dependencies
  gem sources -r "https://artifactory-internal.ps.chef.co/artifactory/omnibus-gems-local/"
}

do_after() {
  build_line "Removing .github directories from vendored gems"
  find "$pkg_prefix/vendor" -type d -name ".github" -exec rm -rf {} + 2>/dev/null || true
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
