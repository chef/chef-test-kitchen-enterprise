# Build and Test

## Prerequisites
- Ruby version compatible with the repository Gemfile
- Bundler installed

## Setup
```bash
bundle install
```

## Common Commands
```bash
# Run full test suite
bundle exec rake test

# Unit-focused tests
bundle exec rake unit

# Integration features
bundle exec rake features

# Style and quality checks
bundle exec rake style
bundle exec rake quality

# Project stats / coverage indicators
bundle exec rake stats
```

## Focused Iteration
```bash
# Run a single spec file
bundle exec ruby -I spec spec/path/to/file_spec.rb

# Run a single cucumber feature
bundle exec cucumber features/some_feature.feature
```

## Practical CI Parity Tips
- Prefer `bundle exec` for all Ruby tooling.
- Run `rake quality` before opening a PR.
- Include failing and passing command output snippets in PR evidence when relevant.

## CI Baseline
Hosted CI exists in this repository (for example [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) and Expeditor pipelines). For reliable local parity, run:

```bash
./support/ci-baseline.sh
```

What it does:
- sets deterministic CI-like environment variables
- configures local bundler path and installs deps
- runs unit tests (`bundle exec rake unit`)
- runs focused verifier regression spec

Optional style step:
- set `RUN_STYLE=1` to include `bundle exec rake style`

Fast path when dependencies are already installed:

```bash
SKIP_BUNDLE_INSTALL=1 ./support/ci-baseline.sh

# Include style checks when local tooling supports it
RUN_STYLE=1 SKIP_BUNDLE_INSTALL=1 ./support/ci-baseline.sh
```

## Dependency Notes
- Core manifests:
	- `Gemfile`
	- `chef-test-kitchen-enterprise.gemspec`
	- `test-kitchen.gemspec`
- Critical runtime layers to watch:
	- SSH stack: `net-ssh`, `net-scp`, `net-ssh-gateway`
	- WinRM stack: `chef-winrm`, `chef-winrm-elevated`, `chef-winrm-fs`
	- CLI/runtime: `thor`, `mixlib-shellout`, `chef-utils`, `chef-licensing`
- Existing safety guard already present: `net-ssh != 7.3.1` in `Gemfile`.
- Conservative hygiene strategy:
	- Prefer major-version upper bounds for open-ended `>=` constraints.
	- Avoid major upgrades in routine maintenance PRs unless explicitly scoped.
	- Prefer tagged releases over `branch: main` for reproducibility when feasible.

See `ai-track-docs/dependency-hygiene.md` for Ex7-specific baseline notes and proposals.

## Viewing Structured Logs
Structured verifier logs include consistent key/value fields:
- `op`
- `status`
- `elapsed_ms`

Feature flag:
- `structured_logs` (default `true`) on `Kitchen::Verifier::Dummy`
- Set `structured_logs: false` in verifier config to disable structured log emission.

Run with log output enabled:

```bash
KITCHEN_LOG=info bundle exec kitchen verify <instance>
```

Then filter structured fields from the Kitchen log:

```bash
grep -E "op=verify status=|elapsed_ms=" .kitchen/logs/kitchen.log
```

## Static Analysis
CI already runs lint/static-analysis checks in `.github/workflows/lint.yml`.

Local equivalents:

```bash
# Full Ruby static analysis
bundle exec cookstyle --chefstyle --display-cop-names

# Targeted path
bundle exec cookstyle --chefstyle --display-cop-names lib/kitchen/verifier/dummy.rb spec/kitchen/verifier/dummy_spec.rb

# Unit gate used by lint workflow
bundle exec rake unit --trace
```

See `ai-track-docs/static-analysis.md` for the full Ex14 baseline and local runbook.
