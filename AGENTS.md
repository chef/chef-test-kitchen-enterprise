# AGENTS.md — chef-test-kitchen-enterprise (TKE Core)

> **For AI coding agents (GitHub Copilot, Codex, Claude, etc.)**
> Read this file before making any changes to this repository.

---

## What This Repo Is

`chef-test-kitchen-enterprise` is the **enterprise fork of Test Kitchen** — a Ruby tool for developing and testing infrastructure code (Chef cookbooks) on isolated target platforms. It is the core orchestration engine: CLI, instance lifecycle, driver/provisioner/verifier plugin loading, state management, and output formatting.

This repo is a **plugin host**. Most feature work for CHEF-23408 lives in `chef/kitchen-agentless`, not here.

---

## Epic Context: CHEF-23408 — Agentless Mode

TKE core changes for this epic are **strictly minimal**. The agentless plugin (`kitchen-agentless`, "KCAI") provides a driver, provisioner, and verifier. TKE core only needs generic extension points that any driver can use — it must not contain agentless-specific logic.

**Status: both TKE-core stories below are complete.** Almost all active/ongoing agentless work now happens in `chef/kitchen-agentless`, not here. Only touch this repo again for this epic if a *new* generic extension point is needed (i.e. something no existing driver/provisioner/verifier hook can express).

### Permitted TKE Core Changes (entire epic)

| File | What Changes | Story | Status |
|------|-------------|-------|--------|
| `lib/kitchen/command/list.rb` | Add generic `driver.source_info` hook — if driver responds to `#source_info`, render an extra section above the instances table | CHEF-36826 | ✅ Done |
| `lib/kitchen/command/destroy.rb` | Add generic `--driver-option` passthrough so plugins can receive destroy-time flags | CHEF-36826 | ✅ Done |
| `lib/kitchen/agentless/` (delete entire dir) | Remove all Waves 1–14 agentless code | CHEF-27348 | ✅ Done |
| `lib/kitchen/provisioner/base.rb` | Remove `#agentless_mode?` method + `default_config :agentless` | CHEF-27348 | ✅ Done |

> ⛔ **No other files in this repo should be modified for CHEF-23408.** If you find yourself editing anything else, stop and re-read the architecture doc — it's almost certainly KCAI plugin work, not TKE core work.

Full architecture: `CHEF-23408-NEW-ARCHITECTURE.md` in this repo.
Full wave plan: `CHEF-23408-WAVE-PLAN.md` in this repo.
Reusable extension guidance: `.github/instructions/agentless-config-extension.instructions.md`.
Common bug patterns and fixes seen across many debugging sessions: `.github/instructions/bug-fix-workflow.instructions.md`.

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

## Lessons Learned From KCAI End-to-End Debugging

Extensive real-target debugging sessions (Docker ephemeral, EC2 ephemeral,
and real-mode static hosts) surfaced a recurring class of issues, almost all
in KCAI rather than TKE core. Captured here so future sessions in either repo
don't have to rediscover them:

- **Three distinct target-credential styles must all be supported without one
  clobbering another**: real-mode static host (credential-map-file), ephemeral
  Docker (dynamically-generated driver state), ephemeral EC2/named-keypair
  (standard TK `transport:` block, resolved via `instance.transport`). See
  `.github/instructions/bug-fix-workflow.instructions.md` for the exact
  resolution priority order and why the ordering matters (TK's SSH transport
  defaults `username` to `"root"`, which is always truthy).
- **The provisioner and verifier duplicate this resolution logic** rather than
  sharing it via inheritance (`ChefInfraAgentless` vs. `InspecAgentless`) — a
  fix in one is easily forgotten in the other. Always check both when fixing
  credential/endpoint bugs.
- **`KITCHEN_YAML` env var** changes which config file `kitchen` reads. If a
  failure references a host/sub-driver that doesn't match the visible
  `kitchen.yml`, check this env var before assuming a regression.
- **Stale `.kitchen/*.yml` state files** persist the previous sub-driver's
  server-id/hostname when a user switches configs without `kitchen destroy`
  first — causes confusing "wrong host"/"credentials not found" errors that
  look like code bugs. Compare file mtimes against the active config.
- **InSpec/Chef license and install-strategy issues** (interactive license
  prompt, `dpkg` permission errors, `license_acceptance/acceptor` load
  failures) are almost always source-node environment/install-strategy
  issues, not KCAI code bugs — but the fix (e.g. `CHEF_LICENSE=accept`,
  running the installer as root) must be applied consistently to **both**
  the chef-client and InSpec invocation paths.

## What NOT to Do

- ❌ Do not add agentless-specific logic to TKE core — use the generic hooks described above
- ❌ Do not modify any file not in the permitted changes table
- ❌ Do not create PRs targeting `main` — always target `agentless-dev-latest`
- ❌ Do not create PRs without the `ai-assisted` label
- ❌ Do not modify `lib/kitchen/version.rb` — managed by Expeditor
- ❌ Do not modify `CHANGELOG.md` — managed by Expeditor
