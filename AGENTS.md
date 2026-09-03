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
| `lib/kitchen/cli.rb`, `lib/kitchen/command/destroy.rb` | Add a `-k/--keep-agentless-source` flag to `kitchen destroy` that applies `keep_agentless_source` as a driver config override before destroy runs | CHEF-36826 |
| `lib/kitchen/agentless/` (delete entire dir) | Remove all Waves 1–14 agentless code | CHEF-27348 |
| `lib/kitchen/provisioner/base.rb` | Remove `#agentless_mode?` method + `default_config :agentless` | CHEF-27348 |

> **Note (CHEF-36826):** `lib/kitchen/command/list.rb` does **not** need a
> TKE core hook. The `kitchen-agentless` plugin already renders the
> agentless-source node inline in `kitchen list` output via its own
> `list_extension.rb` monkeypatch on `Kitchen::Command::List#list_table` —
> a lazily-loaded plugin gem can safely add that at runtime. A CLI flag is
> different: Thor parses ARGV against each command's statically-declared
> options *before* kitchen.yml is read and before any driver plugin is
> `require`d, so a new switch like `--keep-agentless-source` can only be
> registered by TKE core itself — that's the only piece of CHEF-36826 that
> actually needs a TKE core change.

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
│       │   └── destroy.rb       # ← CHEF-36826: --keep-agentless-source flag
│       ├── cli.rb               # ← CHEF-36826: register -k/--keep-agentless-source
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

### CHEF-36826 · `--keep-agentless-source` flag for `kitchen destroy` (Wave 5)

#### `kitchen list` — no TKE core change needed

Originally planned as a generic `driver#source_info` hook in
`lib/kitchen/command/list.rb`, but this turned out to be unnecessary: the
`kitchen-agentless` plugin already renders the agentless-source node inline
via its own `list_extension.rb`, which monkeypatches
`Kitchen::Command::List#list_table` at plugin-load time (lazily-loaded
plugins can freely monkeypatch TK core classes at runtime — this doesn't
require any static CLI/Thor registration, unlike a new command-line
switch). TKE core stays completely agentless-unaware for `kitchen list`.

#### `kitchen destroy` — `-k/--keep-agentless-source` flag

A real CLI flag genuinely requires a TKE core change: Thor parses ARGV
against each command's statically-declared `method_option`s at dispatch
time, **before** `kitchen.yml` is read and before any driver plugin gem is
`require`d. A lazily-loaded plugin therefore cannot register a new switch
— by the time it loads, an unrecognized flag would already have raised
`Thor::UnknownArgumentError`.

```ruby
# lib/kitchen/cli.rb — registers the flag only for the destroy command
if action == :destroy
  method_option :keep_agentless_source,
    aliases: "-k",
    type: :boolean,
    default: false,
    desc: "Do not destroy the agentless-source node ..."
end

# lib/kitchen/command/destroy.rb — applies it as a generic driver config
# override before the destroy action runs; harmless no-op for any driver
# that doesn't read :keep_agentless_source (e.g. Kitchen::Driver::Agentless#keep_source?)
def apply_driver_overrides(instances)
  return unless options[:keep_agentless_source]

  instances.each { |instance| instance.driver.send(:config)[:keep_agentless_source] = true }
end
```

Usage: `kitchen destroy -k` / `kitchen destroy --keep-agentless-source`.
This is purely additive to the existing `KITCHEN_KEEP_AGENTLESS_SOURCE`
env var and kitchen.yml `driver: { keep_agentless_source: true }` routes
already supported entirely from the plugin side — all three routes end up
setting the same `config[:keep_agentless_source]` key that the driver reads.

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
