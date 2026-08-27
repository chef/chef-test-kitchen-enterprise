# GitHub Copilot Instructions for Chef Test Kitchen Enterprise

## 🏗️ Project Overview & Structure

**Chef Test Kitchen Enterprise** is a Ruby-based integration testing tool for developing and testing infrastructure code (particularly Chef cookbooks) on isolated target platforms. This is an enterprise fork of the open-source Test Kitchen project, maintained by Progress Chef Software.

### Core Purpose
Test Kitchen provides a test harness to execute infrastructure code on one or more platforms in isolation. It creates, configures, tests, and destroys virtual machines and containers through a plugin-based architecture.

## Initialization Required

VERY IMPORTANT: If `context/shared/map.md` does not exist, abort the requested task immediately and do not attempt to continue. Note that the path is in a gitignored directory - file_search will fail to find it - you must use file_read with the explicit path. If the file is not found, use the /start-development skill.

To get started with AI-driven development, you must initialize the repo with the /start-development skill. This will set up your environment, clone reference repos, and ensure you have the necessary tools installed. The remainder of this document assumes you have done this.

## Additional Context Required

VERY IMPORTANT: This repos uses dynamic context loading using modular, shared context files. The map of what context files are and what levels of context exist is located at `context/shared/map.md`. You must read and understand this file to understand how to load context. If the file is not found, use the /start-development skill. 

VERY IMPORTANT: Whenever you need to search for information about the project, the codebase, or the domain, you should first consult the shared context files. Use the /search-context skill to do this.
Always use the search-context skill, it knows how to traverse the map.

## Do research using A Skill

When you need to do research, use the skill /search-context.

## Workflow

Nearly all tasks should follow the workflow outlined in `context/shared/by-division/chef/standards/workflow.md`, which provides a step-by-step guide for analysis, implementation, testing, committing code, and creating pull requests.

Exceptions to this: exploration, experimentation,  and analysis tasks may deviate from this workflow, but any implementation work should adhere to it, and you may also write to temporary files without spec or JIRA. Exploratory and experimental work must be on a branch named `throwaway/*` and the branch should be deleted after the work is complete.

## Build, Test & Lint Commands

```bash
# Unit tests only (fast — runs spec/**/*_spec.rb via Minitest)
bundle exec rake unit

# Run a single spec file
bundle exec ruby -Ilib -Ispec spec/kitchen/instance_spec.rb

# Integration tests (Cucumber + Aruba, slower)
bundle exec rake features

# Full test suite (unit + features)
bundle exec rake test

# Style linting (Chefstyle/RuboCop)
bundle exec rake style

# Everything (test + quality checks)
bundle exec rake default

# Bundle install — MUST use the wrapper script (clears VS Code/Copilot git env vars that break bundler)
bash .github/scripts/bundle-install.sh
```

## Architecture

**Instances = Suites × Platforms.** `Kitchen::Config` reads `kitchen.yml` (preferred) or legacy `.kitchen.yml`, cross-products suites and platforms, and constructs immutable `Kitchen::Instance` objects. Each instance is independent and safe for parallel execution.

**Plugin loading convention.** `Kitchen::Plugin.load(type, name, config)` resolves `kitchen/<type>/<name>.rb` (e.g., `kitchen/driver/docker.rb`) and constantizes `Kitchen::Driver::Docker`. External gems follow the same path convention.

**Configurable DSL** (included in all plugin base classes via `Kitchen::Configurable`):
- `default_config :key, value` — static value or computed block
- `required_config :key` — raises `UserError` if nil/missing
- `expand_path_for :key` — auto-expands relative path against `kitchen_root`
- `finalize_config!(instance)` must be called before accessing `config`

**Instance lifecycle FSM:**
```ruby
TRANSITIONS = %i{destroy create converge setup verify}  # lib/kitchen/instance.rb ~line 716
```
`transition_to(:verify)` walks forward through each missing step automatically. State is a plain `Hash` written by the driver (VM identifiers) and read by transport/provisioner — always guard with `state[:key].nil?`.

**Plugin API versioning.** Every plugin class must declare its API version:
```ruby
kitchen_driver_api_version 2   # also: kitchen_provisioner_api_version, kitchen_verifier_api_version
```

**Error taxonomy:**
- `Kitchen::UserError` — user-fixable config or input problems
- `Kitchen::ClientError` — coding errors (e.g., abstract method not implemented in subclass)
- `Kitchen::ActionFailed` — runtime execution failures

## Key Conventions

**Tests use Minitest, not RSpec.** `spec/` uses the Minitest spec DSL (`describe`/`it`/`let`) with Mocha for mocking and FakeFS for filesystem isolation. Standard test doubles are the `Dummy` plugin classes (`Kitchen::Driver::Dummy`, `Kitchen::Provisioner::Dummy`, etc.).

**New plugins.** File goes in `lib/kitchen/<type>/<name>.rb`; test mirrors at `spec/kitchen/<type>/<name>_spec.rb`. Must extend the appropriate `Base` class and declare `kitchen_<type>_api_version 2`.

**Enterprise licensing.** `Kitchen::Licensing::Config` is loaded in `plugin.rb`'s `ensure` block and re-asserted after every plugin load. `provisioner.check_license` is called at converge — no-op in `Base`, overridden in Chef provisioners. Do not remove or reorder the `ensure` block in `lib/kitchen/plugin.rb`.

**License headers.** New `.rb` files require the Apache 2.0 header with:
```
Copyright (c) <year> Progress Software Corporation and/or its subsidiaries or affiliates.
```

**DCO.** All commits must be signed: `git commit --signoff`.
