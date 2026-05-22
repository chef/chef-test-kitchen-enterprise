#!/usr/bin/env bash

# Local CI baseline runner for consistent pre-PR validation.
# This does not replace hosted CI; it provides a reliable local baseline.

set -euo pipefail

export CI="${CI:-true}"
export LANG=C.UTF-8
export LANGUAGE=C.UTF-8

echo "==> Local CI baseline starting"
echo "==> Ruby: $(ruby --version)"
echo "==> Bundler: $(bundle --version)"

if [[ "${SKIP_BUNDLE_INSTALL:-0}" != "1" ]]; then
  echo "==> Configuring bundler path"
  bundle config --local path vendor/bundle

  echo "==> Installing dependencies"
  bundle install --jobs=7 --retry=3
else
  echo "==> SKIP_BUNDLE_INSTALL=1 set; skipping dependency install"
fi

if [[ "${RUN_STYLE:-0}" == "1" ]]; then
  echo "==> Running style checks"
  bundle exec rake style
else
  echo "==> RUN_STYLE=0; skipping style checks"
fi

echo "==> Running unit tests"
bundle exec rake unit

echo "==> Running focused verifier regression"
bundle exec ruby -I spec spec/kitchen/verifier/dummy_spec.rb

echo "==> Local CI baseline passed"
