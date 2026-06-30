export HAB_BLDR_CHANNEL="base-2025"
export HAB_REFRESH_CHANNEL="base-2025"

_ruby_pkg="core/ruby3_4"
pkg_name="chef-test-kitchen-enterprise"
pkg_origin="chef"
pkg_maintainer="The Chef Maintainers <humans@chef.io>"
pkg_description="The Chef Test Kitchen Enterprise"
pkg_license=('Apache-2.0')
pkg_bin_dirs=(
  bin
)
pkg_build_deps=(
  core/make
  core/bash
  core/clang
  core/git
)
pkg_deps=(
  ${_ruby_pkg}
  core/coreutils
  core/cacerts
)
pkg_svc_user=root

pkg_version() {
  # The aarch64-darwin plan lives under habitat/aarch64-darwin,
  # so read VERSION from the repository root via PLAN_CONTEXT.
  cat "$PLAN_CONTEXT/../../VERSION"
}

do_before() {
  update_pkg_version
}

do_unpack() {
  mkdir -pv "$HAB_CACHE_SRC_PATH/$pkg_dirname"
  cp -RT "$PLAN_CONTEXT"/../.. "$HAB_CACHE_SRC_PATH/$pkg_dirname/"
}

do_setup_environment() {
  set_runtime_env GEM_HOME "${pkg_prefix}/vendor"
  set_runtime_env GEM_PATH "${pkg_prefix}/vendor"
  set_runtime_env APPBUNDLER_ALLOW_RVM "true" # keep runtime GEM_PATH intact for appbundler binstubs
  set_runtime_env LANG "en_US.UTF-8"
  set_runtime_env LC_CTYPE "en_US.UTF-8"
  set_runtime_env CHEF_TEST_KITCHEN_ENTERPRISE "true"
}

do_prepare() {
  build_line "Setting up build environment for native extensions"
  export CC="$(pkg_path_for core/clang)/bin/clang"
  export CXX="$(pkg_path_for core/clang)/bin/clang++"
}

do_build() {
  cd "$HAB_CACHE_SRC_PATH/$pkg_dirname" || exit_with "unable to cd to source directory" 1

  export GEM_HOME="$pkg_prefix/vendor"
  export CC="$(pkg_path_for core/clang)/bin/clang"
  export CXX="$(pkg_path_for core/clang)/bin/clang++"

  build_line "Setting GEM_PATH=$GEM_HOME"
  export GEM_PATH="$GEM_HOME"
  export CHEF_TEST_KITCHEN_ENTERPRISE="true"

  # Redirect HOME to a writable path inside the build tree so that rubygems and
  # bundler don't try to stat /Users/<user> (inaccessible inside the studio).
  export HOME="$HAB_CACHE_SRC_PATH/$pkg_dirname"
  export GEM_SPEC_CACHE="$HAB_CACHE_SRC_PATH/$pkg_dirname/.gem/specs"
  mkdir -p "$GEM_SPEC_CACHE"

  # The Habitat studio on macOS resets HOME and git credentials, so bundle install
  # cannot authenticate to private GitHub repos (kitchen-chef-enterprise). Gems are
  # pre-installed into vendor/bundle by the workflow's "Bundle Install" step (outside
  # the studio, using system Ruby with PAT auth). For local dev: run
  # `bundle install --path vendor/bundle` before `hab studio build`.
  ruby_ver=$(ls vendor/bundle/ruby/ 2>/dev/null | sort | tail -n1)
  if [[ -z "$ruby_ver" ]] || [[ ! -d "vendor/bundle/ruby/${ruby_ver}/cache" ]]; then
    exit_with "vendor/bundle not found. Run 'bundle install --path vendor/bundle' before building." 1
  fi

  build_line "Installing gems from vendor/bundle/ruby/${ruby_ver}/cache/ into GEM_HOME"
  mkdir -p "$GEM_HOME/cache"
  cp -n "vendor/bundle/ruby/${ruby_ver}/cache/"*.gem "$GEM_HOME/cache/" 2>/dev/null || true

  gem_count=$(ls "$GEM_HOME/cache/"*.gem 2>/dev/null | wc -l | tr -d ' ')
  build_line "Installing ${gem_count} gems from cache into GEM_HOME"
  # Install libyajl2 first — ffi-yajl's extconf.rb does `require "libyajl2"` at compile time.
  gem install --local --no-document --force --ignore-dependencies "$GEM_HOME/cache/libyajl2-"*.gem
  # Install the rest in batches to avoid ARG_MAX limits.
  ls "$GEM_HOME/cache/"*.gem | grep -v libyajl2 | xargs -n 10 gem install --local --no-document --force --ignore-dependencies

  # Seed git gems (kitchen-chef-enterprise, kitchen-dokken) into bundler/gems/
  # so post-bundle-install.rb can find and rebuild their extensions.
  if [[ -d "vendor/bundle/ruby/${ruby_ver}/bundler/gems" ]]; then
    mkdir -p "$GEM_HOME/bundler/gems"
    cp -Rn "vendor/bundle/ruby/${ruby_ver}/bundler/gems/"* "$GEM_HOME/bundler/gems/" 2>/dev/null || true
  fi

  # Update Gemfile.lock to reflect the current package version.
  # Appbundler reads the lockfile to pin gem versions; if it's stale it raises
  # Gem::MissingSpecVersionError. Only the bare-version spec line changes
  # (e.g. "    chef-test-kitchen-enterprise (2.0.12)"); constraint lines
  # like "(>= 2.0.12)" are left unchanged.
  _lock_ver=$(ruby -e "puts File.read('VERSION').strip")
  build_line "Updating Gemfile.lock: chef-test-kitchen-enterprise → ${_lock_ver}"
  sed -i "s/^\(    chef-test-kitchen-enterprise\) ([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*)/\1 (${_lock_ver})/" Gemfile.lock

  ruby ./cleanup_gem_lockfiles.rb
  ruby ./post-bundle-install.rb

  gem build chef-test-kitchen-enterprise.gemspec
  gem build test-kitchen.gemspec
}

do_install() {
  cd "$HAB_CACHE_SRC_PATH/$pkg_dirname" || exit_with "unable to cd to source directory" 1

  if [[ -f "NOTICE" ]]; then
    build_line "Copying NOTICE to package directory"
    cp "NOTICE" "$pkg_prefix/"
  else
    build_line "Warning: NOTICE not found in source directory"
  fi

  export GEM_HOME="$pkg_prefix/vendor"
  export HOME="$HAB_CACHE_SRC_PATH/$pkg_dirname"
  export GEM_SPEC_CACHE="$HAB_CACHE_SRC_PATH/$pkg_dirname/.gem/specs"
  mkdir -p "$GEM_SPEC_CACHE"

  build_line "Setting GEM_PATH=$GEM_HOME"
  export GEM_PATH="$GEM_HOME"

  # Ensure bundler and appbundler are available for binstub generation
  build_line "Installing bundler and appbundler"
  gem install bundler --no-document
  gem install appbundler --no-document

  cleanup_community_test_kitchen_gem

  gem install --local "chef-test-kitchen-enterprise-$(pkg_version).gem" --no-document --force --ignore-dependencies
  gem install --local test-kitchen-*.gem --no-document --force --ignore-dependencies

  make_pkg_official_distrib

  build_line "Generating appbundler binstubs with precise version pins"
  cd "$HAB_CACHE_SRC_PATH/$pkg_dirname" || exit_with "unable to cd to source directory" 1
  
  # Set LOAD_PATH to include lib so appbundler can load test-kitchen.gemspec which requires kitchen/version
  export RUBYLIB="$HAB_CACHE_SRC_PATH/$pkg_dirname/lib:${RUBYLIB:-}"
  
  # Pass the bundle directory (source) to appbundler instead of current directory
  # Allow appbundler to continue even if lockfile generation fails (e.g., due to internal gem dependencies)
  # The binstubs should still be generated even if the lockfile step fails
  "$pkg_prefix/vendor/bin/appbundler" "$HAB_CACHE_SRC_PATH/$pkg_dirname" "$pkg_prefix/bin" "chef-test-kitchen-enterprise" || true

  build_line "Patching generated binstubs for Habitat runtime env"
  patch_file="$PLAN_CONTEXT/../binstub_patch.rb"
  for binstub in "$pkg_prefix"/bin/*; do
    if [[ -f "$binstub" ]]; then
      sed -i -e "/require ['\"']rubygems['\"']/r ${patch_file}" "$binstub"
    fi
  done

  if [[ ! -f "$pkg_prefix/bin/kitchen" ]]; then
    build_line "ERROR: kitchen binstub was not created by appbundler"
    return 1
  fi

  if ! grep -q 'APPBUNDLER_ALLOW_RVM' "$pkg_prefix/bin/kitchen"; then
    build_line "ERROR: binstub patch injection failed for $pkg_prefix/bin/kitchen"
    return 1
  fi

  build_line "Successfully generated kitchen binstubs"
}

make_pkg_official_distrib() {
  # Install chef-official-distribution without dependencies since bundler already installed everything.
  build_line "Installing chef-official-distribution gem (package-level only)"
  gem source --add "https://artifactory-internal.ps.chef.co/artifactory/omnibus-gems-local/" || true
  gem install chef-official-distribution --no-document --install-dir "$GEM_HOME" --ignore-dependencies || \
    build_line "Warning: chef-official-distribution unavailable (Artifactory unreachable) — skipping"
  gem sources -r "https://artifactory-internal.ps.chef.co/artifactory/omnibus-gems-local/" 2>/dev/null || true
}

do_after() {
  build_line "Removing .github directories from vendored gems"
  find "$pkg_prefix/vendor" -type d -name ".github" -exec rm -rf {} + 2>/dev/null || true
}

do_strip() {
  return 0
}

# Some kitchen plugins may install the community test-kitchen gem as a dependency.
# This can conflict with the alias gem provided by chef-test-kitchen-enterprise.
cleanup_community_test_kitchen_gem() {
  if gem list -i "^test-kitchen$" > /dev/null 2>&1; then
    build_line "Removing community test-kitchen gem to avoid alias gem conflicts"
    gem uninstall test-kitchen --all --ignore-dependencies --executables || true
  fi
}
