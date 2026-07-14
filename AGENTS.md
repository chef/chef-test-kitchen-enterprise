# AGENTS.md — chef-test-kitchen-enterprise (TKE Core)

> **For AI coding agents (GitHub Copilot, Codex, Claude, etc.)**
> Read this file before making any changes to this repository.

---

## What This Repo Is

`chef-test-kitchen-enterprise` is the **enterprise fork of Test Kitchen** — a Ruby tool for developing and testing infrastructure code (Chef cookbooks) on isolated target platforms. It is the core orchestration engine: CLI, instance lifecycle, driver/provisioner/verifier plugin loading, state management, and output formatting.

This repo is a **plugin host**. Most feature work for CHEF-23408 lives in `chef/kitchen-chef-infra-agentless`, not here.

---

## Epic Context: CHEF-23408 — Agentless Mode

TKE core changes for this epic are **strictly minimal**. The agentless plugin (`kitchen-chef-infra-agentless`) provides a driver, provisioner, and verifier. TKE core only needs generic extension points that any driver can use — it must not contain agentless-specific logic.

### Permitted TKE Core Changes (entire epic)

| File | What Changes | Story |
|------|-------------|-------|
| `lib/kitchen/command/list.rb` | Add generic `driver.source_info` hook — if driver responds to `#source_info`, render an extra section above the instances table | CHEF-36826 |
| `lib/kitchen/command/destroy.rb` | Add generic `--driver-option` passthrough so plugins can receive destroy-time flags | CHEF-36826 |
| `lib/kitchen/agentless/` (delete entire dir) | Remove all Waves 1–14 agentless code | CHEF-27348 |
| `lib/kitchen/provisioner/base.rb` | Remove `#agentless_mode?` method + `default_config :agentless` | CHEF-27348 |

> ⛔ **No other files in this repo should be modified for CHEF-23408.** If you find yourself editing anything else, stop and re-read the architecture doc.

Full architecture: `CHEF-23408-NEW-ARCHITECTURE.md` in this repo.
Full wave plan: `CHEF-23408-WAVE-PLAN.md` in this repo.

---

## Development Workflow Rules

### Branch Strategy

- **All feature branches must be checked out from `agentless-dev-latest`**
- **All PRs must target `agentless-dev-latest`** (never `main` directly)
- Branch naming: `<JIRA-KEY>` — e.g. `CHEF-27348`, `CHEF-36826`

```bash
git fetch origin
git checkout agentless-dev-latest
git pull origin agentless-dev-latest
git checkout -b CHEF-XXXXX
```

### PR Requirements

Every PR must have:

- **`ai-assisted` label** (mandatory, no exceptions)
- Base branch: `agentless-dev-latest`
- Title: `CHEF-XXXXX: <description>`
- DCO signoff on all commits (`git commit --signoff`)
- Tests passing

```bash
gh pr create \
  --base agentless-dev-latest \
  --title "CHEF-XXXXX: description" \
  --label "ai-assisted" \
  --body "..."
```

---

## Repository Structure

```text
chef-test-kitchen-enterprise/
├── bin/
│   └── kitchen                  # CLI entry point (rarely changed)
├── lib/
│   └── kitchen/
│       ├── command/             # CLI command implementations
│       │   ├── list.rb          # ← CHEF-36826: add source_info hook
│       │   └── destroy.rb       # ← CHEF-36826: add driver-option passthrough
│       ├── driver/              # Driver base classes
│       ├── provisioner/
│       │   └── base.rb          # ← CHEF-27348: remove agentless_mode? + default_config
│       ├── transport/           # SSH, WinRM transport layers
│       ├── verifier/            # Verifier base classes
│       ├── agentless/           # ← CHEF-27348: DELETE this entire directory
│       │   ├── context.rb
│       │   ├── credential_resolver.rb
│       │   ├── remote_node.rb
│       │   └── warnings.rb
│       ├── instance.rb          # Core instance orchestration
│       └── kitchen.rb           # Main entry point
├── spec/                        # Minitest unit tests
├── features/                    # Cucumber integration tests
├── AGENTS.md                    # This file
├── CHEF-23408-NEW-ARCHITECTURE.md
└── CHEF-23408-WAVE-PLAN.md
```

---

## The Two TKE Core Stories

### CHEF-27348 · Waves 1–14 Cleanup (Wave 1 — do this first)

**Goal:** Remove all agentless-specific code from TKE core, ensuring non-agentless kitchen.yml files continue to work unchanged.

**What to delete:**

```bash
rm -rf lib/kitchen/agentless/
```

**What to remove from `lib/kitchen/provisioner/base.rb`:**

```ruby
# Remove these:
default_config :agentless, {}

def agentless_mode?
  # ...
end
```

**Verification:**

```bash
bundle exec rake test   # all existing tests must still pass
```

**Key principle:** Non-agentless kitchen.yml files must be completely unaffected. The agentless driver, not TKE core, validates agentless config.

---

### CHEF-36826 · Generic Driver Hooks for `kitchen list` and `kitchen destroy` (Wave 5)

#### `kitchen list` — `#source_info` hook

Add a generic hook to `lib/kitchen/command/list.rb`. If the driver for any instance responds to `#source_info`, render an extra section:

```ruby
# lib/kitchen/command/list.rb — generic, agentless-unaware
def print_table(instances)
  # Render source section if driver provides it (only once, first instance wins)
  source = instances.first&.driver&.respond_to?(:source_info) &&
           instances.first.driver.source_info
  if source
    print_source_section(source)
  end
  # ... existing instances table rendering ...
end

def print_source_section(info)
  # Renders: Instance | Driver | State | Endpoint | CIC Ver | InSpec Ver
  # info is a Hash with keys: :instance, :driver, :state, :endpoint, :cic_version, :inspec_version
end
```

TKE core does not know what "agentless-source" is — it just renders whatever `#source_info` returns.

#### `kitchen destroy` — `--driver-option` passthrough

Add a generic `--driver-option key=value` flag to the destroy command so plugins can receive destroy-time options:

```ruby
# The AgentlessDriver reads: options[:keep_source]
# User runs: kitchen destroy --driver-option keep_source=true
```

Exact implementation approach to be confirmed against TKE core's Thor CLI setup in Wave 5 (CHEF-36826).

---

## Running Tests

```bash
# Install dependencies
bundle install

# Run all unit tests
bundle exec rake unit

# Run integration tests (Cucumber)
bundle exec rake features

# Run all tests
bundle exec rake test

# Style checks
bundle exec rake style

# All quality checks
bundle exec rake quality
```

**Do not break existing tests.** Every PR must pass `bundle exec rake test` before merging.

---

## Code Conventions

- **Linter:** Chefstyle (`bundle exec cookstyle --chefstyle -a` — auto-corrects)
- **Ruby:** 3.1+
- **Test framework:** Minitest + Mocha
- **Error classes:** `Kitchen::UserError` (user errors), `Kitchen::ClientError` (internal errors)
- **Logging:** `info()`, `warn()`, `debug()` — never `puts`
- **License header:** Apache 2.0 on all new `.rb` files

---

## What NOT to Do

- ❌ Do not add agentless-specific logic to TKE core — use the generic hooks described above
- ❌ Do not modify any file not in the permitted changes table
- ❌ Do not create PRs targeting `main` — always target `agentless-dev-latest`
- ❌ Do not create PRs without the `ai-assisted` label
- ❌ Do not modify `lib/kitchen/version.rb` — managed by Expeditor
- ❌ Do not modify `CHANGELOG.md` — managed by Expeditor
