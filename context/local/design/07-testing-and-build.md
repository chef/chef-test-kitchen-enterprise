# Testing & Build

## Test layers

The project uses two complementary test layers plus style enforcement.

| Layer | Framework | Location | Rake task |
| ----- | --------- | -------- | --------- |
| Unit | Minitest (+ Mocha, FakeFS) | `spec/` | `rake unit` |
| Integration | Cucumber (+ Aruba) | `features/` | `rake features` |
| Style | RuboCop w/ Chefstyle | `lib/`, `spec/` | `rake style` |

### Unit tests (`spec/`)

- Uses **Minitest** spec syntax (`describe`/`it`, `_(...).must_equal`), not
  RSpec — despite the `spec/` directory name.
- `spec/spec_helper.rb` wires: `minitest/autorun`, `mocha/minitest` for
  stubbing/mocking, and `fakefs/safe` for filesystem isolation.
- The tree under `spec/kitchen/` mirrors `lib/kitchen/`.
- Typical pattern: stub an `instance` (name, logger, suite, platform), build the
  plugin with a config hash, call `finalize_config!(instance)`, then assert on
  resolved config, behavior, and log output.

### Integration tests (`features/`)

- **Cucumber** feature files exercise the CLI end-to-end, driven by **Aruba**
  (runs the `kitchen` binary in a sandbox and asserts on exit codes / output).
- Coverage includes `kitchen_command`, `kitchen_action_commands`,
  `kitchen_list_command`, `kitchen_login_command`, `kitchen_diagnose_command`,
  `kitchen_init_command`, `kitchen_console_command`, `kitchen_test_command`,
  `kitchen_help_command`, `kitchen_defaults`, and `kitchen_sink_command`.
- Step definitions live in `features/step_definitions/`.

## Rake tasks (`Rakefile`)

```
rake unit        # Minitest unit suite (rake/testtask over spec/**)
rake features    # Cucumber integration suite
rake test        # => [unit, features]
rake style       # RuboCop with --chefstyle
rake stats       # LOC statistics
rake quality     # => [style, stats]
rake             # default => [test, quality]
```

Gem packaging tasks are set up for **both** gem names:
- `chef-test-kitchen-enterprise` (primary, via `Bundler::GemHelper`).
- `test-kitchen` alias gem (namespace `alias:`, using `test-kitchen.gemspec`).
- `rake build:all` builds both.

## Dependency wrapper (`.github/scripts/bundle-install.sh`)

`bundle install` must be run through this wrapper rather than directly. VS Code
and the Copilot CLI inject git environment variables (`GIT_DIR`,
`GIT_WORK_TREE`, `GIT_CONFIG_PARAMETERS`, the `GIT_CONFIG_KEY_*` /
`GIT_CONFIG_VALUE_*` pairs, etc.) that make Bundler treat its cached git-sourced
gem clones as **bare repositories**, breaking `git rev-parse`/`git fetch`. The
wrapper unsets those variables before invoking `bundle`, then runs the install.

> Practical note observed during setup: several transitive gems
> (`license-acceptance`, `mixlib-cli`, `mixlib-config`, `corefoundation`, ...)
> had specific pinned versions yanked from RubyGems. Recovery is a
> `bundle update` to re-resolve to available versions, after which the wrapper
> `bundle install` completes cleanly (272 gems).

## CI / Release (Expeditor + Buildkite)

- CI/CD is orchestrated by **Expeditor** (`.expeditor/config.yml`) with Buildkite
  pipelines. The PR-verification pipeline is `habitat/test`
  (`.expeditor/habitat-test.pipeline.yml`, `trigger: pull_request`), which builds
  and tests the Habitat artifact.
- Version bumps, changelog entries, and Habitat builds are automated on merge and
  controlled via `Expeditor: *` PR labels — the ones actually wired up in
  `config.yml` are `Bump Version Minor`, `Bump Version Major`,
  `Skip Version Bump`, and `Skip Habitat`.
- `lib/kitchen/version.rb`, `CHANGELOG.md`, and `.expeditor/config.yml` are
  Expeditor-managed and should not be hand-edited.
- Packaging/distribution targets **Habitat** (`habitat/` + the
  `.expeditor/build.habitat.*` pipelines), including an aarch64-linux build. (The
  `chefes/omnibus-toolchain` image is used only as a build container; there is no
  separate Omnibus package pipeline in this repo.)

## Requirements for contributions

- **DCO sign-off** (`git commit --signoff`) is mandatory; CI fails without it.
- New Ruby files need the Apache-2.0 license header.
- Chefstyle (`rake style`) must pass.
- Unit tests are expected for new/changed behavior (repo guidance targets
  >80% coverage on touched code).
