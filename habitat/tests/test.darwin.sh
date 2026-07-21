#!/usr/bin/env bash

set -euo pipefail

export CHEF_LICENSE="accept-no-persist"
export HAB_LICENSE="accept-no-persist"
export HAB_NONINTERACTIVE="true"
export HAB_BLDR_CHANNEL="base-2025"

project_root="$(git rev-parse --show-toplevel)"
pkg_ident="$1"

error() {
  local message="$1"
  echo -e "\nERROR: ${message}\n" >&2
  exit 1
}

[[ -n "$pkg_ident" ]] || error "no hab package identity provided"

package_version=$(awk -F / '{print $3}' <<<"$pkg_ident")
pkg_path=$(hab pkg path "$pkg_ident")

echo "--- :mag_right: Testing ${pkg_ident} executables at ${pkg_path}"

# Verify kitchen version matches the package version
actual_version=$("${pkg_path}/bin/kitchen" -v | sed -E 's/.*Version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
echo "Detected version: $actual_version"
[[ "$package_version" = "$actual_version" ]] || error "kitchen version mismatch. Expected '$package_version', got '$actual_version'"

echo "--- :kitchen: Running kitchen smoke test"

cd "${project_root}"

[[ -f "${project_root}/kitchen.dummy.yml" ]] || error "${project_root}/kitchen.dummy.yml not found"

export KITCHEN_LOCAL_YAML="${project_root}/kitchen.dummy.yml"

"${pkg_path}/bin/kitchen" diagnose all || error "kitchen diagnose failed"
"${pkg_path}/bin/kitchen" list       || error "kitchen list failed"

"${pkg_path}/bin/kitchen" converge default-localhost || error "kitchen converge failed"
"${pkg_path}/bin/kitchen" verify  default-localhost  || error "kitchen verify failed"
"${pkg_path}/bin/kitchen" destroy default-localhost  || error "kitchen destroy failed"

echo "--- :white_check_mark: All tests passed for ${pkg_ident}"
