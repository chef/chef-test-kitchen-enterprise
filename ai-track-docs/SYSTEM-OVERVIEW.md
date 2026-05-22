# System Overview

## Purpose
Test Kitchen Enterprise is a Ruby-based integration test harness for infrastructure code. It orchestrates lifecycle actions (`create`, `converge`, `verify`, `destroy`) across drivers, provisioners, transports, and verifiers.

## Languages and Key Assets
- Ruby (primary): `lib/`, `bin/`, `spec/`, `Rakefile`, `Gemfile`
- Gherkin (integration scenarios): `features/*.feature`
- YAML (configuration): `kitchen.yml`, `kitchen.*.yml`, `cucumber.yml`
- Markdown (documentation): `README.md`, `docs/`, `ai-track-docs/`

## Entry Points (Concrete Paths)
- CLI executable: `bin/kitchen`
- CLI command router (Thor): `lib/kitchen/cli.rb`
- Library bootstrap and shared constants/logger setup: `lib/kitchen.rb`
- Build/test task entrypoint: `Rakefile`
- Default project config: `kitchen.yml`
- Integration test profile config: `cucumber.yml`

## Core Runtime Model
- Primary library root: `lib/kitchen/`
- Plugin domains:
  - `lib/kitchen/driver/` provisions target environments
  - `lib/kitchen/provisioner/` applies desired state (Chef, shell, etc.)
  - `lib/kitchen/transport/` executes remote commands (SSH, WinRM, etc.)
  - `lib/kitchen/verifier/` runs validation frameworks (for example InSpec)
- Config surfaces:
  - Project-level Kitchen YAML (`kitchen.yml` and related variants)
  - Suite/platform matrix expanded into instance objects at runtime

## Execution Flow
1. User invokes a Kitchen command.
2. Kitchen resolves config into instances (suite x platform).
3. Driver allocates infrastructure and returns connection state.
4. Provisioner converges target nodes.
5. Verifier runs checks and reports outcomes.
6. Driver destroys instances unless intentionally retained.

## Test Approach
- Unit/component tests (Minitest style): `spec/**/*_spec.rb`
- Integration behavior tests (Cucumber): `features/*.feature` and `features/step_definitions/`
- Rake tasks in `Rakefile`:
  - `bundle exec rake unit`
  - `bundle exec rake features`
  - `bundle exec rake test`
  - `bundle exec rake style`
  - `bundle exec rake quality`
  - `bundle exec rake stats`
- Supporting examples/fixtures: `examples/`, `test/`, `testing/`

## Low-Risk Modules Safe To Modify
1. `lib/kitchen/driver/dummy.rb`
   - Designed as a simulation driver and covered by `spec/kitchen/driver/dummy_spec.rb`.
2. `lib/kitchen/provisioner/dummy.rb`
   - Self-contained simulation behavior and covered by `spec/kitchen/provisioner/dummy_spec.rb`.
3. `lib/kitchen/verifier/dummy.rb`
   - Small surface area and covered by `spec/kitchen/verifier/dummy_spec.rb`.

## Recommended Module
- Recommended: `lib/kitchen/verifier/dummy.rb`
- Why low risk:
  - It is a non-production simulation plugin (debug/development oriented).
  - Behavior is narrow (`call`, `sleep_if_set`, `failure_if_set`, `randomly_fail?`).
  - Dedicated tests exist in `spec/kitchen/verifier/dummy_spec.rb`.
  - Lower blast radius than core transport implementations (`ssh.rb`, `winrm.rb`) or CLI routing.

## Assumptions and How To Verify
- Assumption: Dummy modules are intentionally safe simulation plugins.
  - Verify: read module docs/comments in `lib/kitchen/driver/dummy.rb`, `lib/kitchen/provisioner/dummy.rb`, `lib/kitchen/verifier/dummy.rb`.
- Assumption: Entry-point paths listed above are active runtime/build entry points.
  - Verify: inspect `bin/kitchen`, `lib/kitchen/cli.rb`, `lib/kitchen.rb`, and `Rakefile`.
- Assumption: Unit/integration test approach is accurately wired through Rake tasks.
  - Verify: run `bundle exec rake -T` and confirm `unit`, `features`, and `test` tasks.
- Assumption: Changing `lib/kitchen/verifier/dummy.rb` has low system-wide impact.
  - Verify: run `bundle exec ruby -I spec spec/kitchen/verifier/dummy_spec.rb` and then `bundle exec rake unit`.

## Build and Release Notes
- Rake tasks drive quality/test workflows.
- Gem packaging metadata is in gemspec files.
- CI/release orchestration is configured under `.expeditor/` and `.buildkite/`.
