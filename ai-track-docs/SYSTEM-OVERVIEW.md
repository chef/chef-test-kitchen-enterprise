# System Overview

## Purpose
Test Kitchen Enterprise is a Ruby-based integration test harness for infrastructure code. It orchestrates lifecycle actions (`create`, `converge`, `verify`, `destroy`) across drivers, provisioners, transports, and verifiers.

## Core Runtime Model
- CLI entrypoint: `bin/kitchen`
- Primary library root: `lib/kitchen/`
- Plugin domains:
  - `driver/` provisions target environments
  - `provisioner/` applies desired state (Chef, shell, etc.)
  - `transport/` executes remote commands (SSH, WinRM, etc.)
  - `verifier/` runs validation frameworks (for example InSpec)
- Config surfaces:
  - Project-level kitchen YAML files (for example `kitchen.yml`)
  - Suite/platform matrices and per-instance overrides

## Execution Flow
1. User invokes a Kitchen command.
2. Kitchen resolves config into instances (suite x platform).
3. Driver allocates infrastructure and returns connection state.
4. Provisioner converges target nodes.
5. Verifier runs checks and reports outcomes.
6. Driver destroys instances unless intentionally retained.

## Testing Surfaces
- Unit and component tests: `spec/`
- Integration behavior tests: `features/` (Cucumber)
- Examples and fixtures: `examples/`, `test/`, `testing/`

## Build and Release Notes
- Rake tasks drive quality/test workflows.
- Gem packaging metadata is in gemspec files.
- CI/release orchestration is configured under `.expeditor/` and `.buildkite/`.
