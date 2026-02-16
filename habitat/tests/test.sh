#!/usr/bin/env bash

set -euo pipefail

export CHEF_LICENSE="accept-no-persist"
export HAB_LICENSE="accept-no-persist"
export HAB_NONINTERACTIVE="true"
export HAB_BLDR_CHANNEL="base-2025"

project_root="$(git rev-parse --show-toplevel)"
pkg_ident="$1"

# print error message followed by usage and exit
error () {
  local message="$1"

  echo -e "\nERROR: ${message}\n" >&2

  exit 1
}

[[ -n "$pkg_ident" ]] || error 'no hab package identity provided'

package_version=$(awk -F / '{print $3}' <<<"$pkg_ident")

cd "${project_root}"

echo "--- :mag_right: Testing ${pkg_ident} executables"
actual_version=$(hab pkg exec "${pkg_ident}" kitchen -- -v | sed -E 's/.*Version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
[[ "$package_version" = "$actual_version" ]] || error "test-kitchen is not the expected version. Expected '$package_version', got '$actual_version'"

echo "--- :kitchen: Running kitchen converge smoke test"

[[ -f "${project_root}/kitchen.dummy.yml" ]] || error "${project_root}/kitchen.dummy.yml not found; cannot run kitchen converge smoke test"

# Use a driver/transport combo that doesn't require external infrastructure.
export KITCHEN_LOCAL_YAML="${project_root}/kitchen.dummy.yml"

kitchen diagnose all || error "kitchen diagnose failed"
kitchen list || error "kitchen list failed"

# Only converge the localhost instance; kitchen.dummy.yml also defines a windows platform.
kitchen converge default-localhost || error "kitchen converge default-localhost failed"

# Verify the instance.
kitchen verify default-localhost || error "kitchen verify default-localhost failed"

# Best-effort cleanup so CI workspaces stay clean.
kitchen destroy default-localhost || error "kitchen destroy default-localhost failed"
