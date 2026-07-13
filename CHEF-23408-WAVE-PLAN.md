# CHEF-23408 — Implementation Wave Plan v1

> **Epic:** Agentless Mode for Test Kitchen Enterprise
> **Total active stories:** 19 (15 existing + 4 new)
> **Closed:** CHEF-34459 (Obsolete — parallel runs)
> **Created:** 2026-07-08

---

## Wave Overview

| Wave | Theme | Stories | Parallel Tracks | Est. Effort |
|------|-------|---------|-----------------|-------------|
| **1** | Core Framework | 3 | 2 | Foundation |
| **2** | Credential System + Source Lifecycle | 5 | 2 | Medium |
| **3** | Provisioner + Sub-Drivers | 4 | 2 | Large |
| **4** | Verifier + Mode Variants | 3 | 2 | Medium |
| **5** | Advanced Features + UX | 3 | 2 | Medium |
| **6** | Documentation + QA | 2 | 1 | Light |

---

## Dependency Graph (Simplified)

```
Wave 1: CHEF-36823 ──┬── CHEF-34610
        (Superdriver) │   (Assignment)
                      │
        CHEF-27348 ───┘   (Backward compat — parallel)
              │
              ▼
Wave 2: CHEF-27354 ──┬── CHEF-27346 ── CHEF-27355
        (CredMgr)    │   (Masking)     (Passphrase)
                     │
        CHEF-27350 ──┘   (Source lifecycle — parallel track)
              │
              ▼
Wave 3: CHEF-27349 ──┬── CHEF-27353
        (Provisioner) │   (Output streaming)
                      │
        CHEF-36824 ───┘   (EC2 + Docker sub-drivers — parallel track)
              │
              ▼
Wave 4: CHEF-36825 ──┬── CHEF-27351
        (Verifier)   │   (Real mode converge)
                     │
        CHEF-27352 ──┘   (Container mode converge — parallel track)
              │
              ▼
Wave 5: CHEF-27347 ──┬── CHEF-34937
        (Errors)     │   (ERB templating)
                     │
        CHEF-36826 ──┘   (Lifecycle UX — parallel track)
              │
              ▼
Wave 6: CHEF-27345 ──── CHEF-34938
        (Docs)          (Qmetry)
        
        CHEF-34939 ← WinRM/Windows (can start from Wave 4 onwards)
```

---

## Wave 1: Core Framework

> **Goal:** Build the superdriver skeleton, config parsing, assignment validation, and backward compatibility. After this wave, `kitchen list` should load an agentless kitchen.yml without errors.

### Track A — Superdriver Core (sequential — blocks everything)

#### CHEF-36823 · Superdriver: `Kitchen::Driver::Agentless` Core Architecture

**What to build:**
- `Kitchen::Driver::Agentless` — superdriver shell with `sub_driver:` delegation
- `Kitchen::Driver::AgentlessSource` — thin adapter for source node config overrides
- `Kitchen::Agentless::Config` — parse + validate `driver.agentless:` block
- `Kitchen::Agentless::RemoteNode` — value object per target node
- `source_node.mode: local` — skip source VM creation; verify `chef-client` in PATH
- Config inheritance resolution: `remote_nodes[name].driver` → `platform.driver` → `driver:`
- **Concurrency guard:** File-lock (`~/.kitchen/agentless-source.lock`) around source creation to prevent race conditions with `kitchen -c N`

**Key deliverables:**
- `lib/kitchen/driver/agentless.rb`
- `lib/kitchen/driver/agentless_source.rb`
- `lib/kitchen/agentless/config.rb`
- `lib/kitchen/agentless/remote_node.rb`
- Unit tests for all classes (>80% coverage)

**Acceptance criteria:**
- [ ] `kitchen list` with agentless kitchen.yml loads config and shows instances
- [ ] `source_node.mode: local` skips source creation, raises UserError if chef-client not in PATH
- [ ] Config inheritance resolves correctly (3-level priority)
- [ ] Sub-driver gem not installed → clear `UserError` (not `LoadError`)

---

#### CHEF-34610 · Target Node Assignment — Explicit Hash Validation

**What to build:**
- Validate `remote_nodes:` is a Hash (not Array)
- Array detected → `UserError` with migration instructions
- Missing instance name in hash → `UserError` at config load
- `driver:` key inside `remote_nodes` entry under `volatility: real` → `UserError`
- `agentless-source` reserved name collision → `UserError`

**Tight coupling:** This is effectively the validation layer of `Kitchen::Agentless::Config` from CHEF-36823. Implement in the same `config.rb` file, but track as a separate story for scope clarity.

**Acceptance criteria:**
- [ ] Array `remote_nodes` raises UserError with migration message
- [ ] Missing instance → UserError at config load (not at converge time)
- [ ] `driver:` key in real-mode remote_node → UserError
- [ ] Suite `agentless` + platform `source` → UserError (reserved name)

---

### Track B — Backward Compatibility (parallel with Track A)

#### CHEF-27348 · Maintain Backward Compatibility

**What to build:**
- Ensure non-agentless kitchen.yml files work exactly as before
- Validation is at driver level: if `driver.name != 'agentless'`, no agentless code runs
- Remove Waves 1-14 agentless code from TKE core:
  - Delete `lib/kitchen/agentless/context.rb`
  - Delete `lib/kitchen/agentless/credential_resolver.rb`
  - Delete `lib/kitchen/agentless/warnings.rb`
  - Remove `#agentless_mode?` and `default_config :agentless` from `Kitchen::Provisioner::Base`
- Integration test: standard (non-agentless) kitchen.yml still works end-to-end

**Note:** This is the **TKE core cleanup story**. All Waves 1-14 agentless code in TKE core is removed here. New agentless code lives only in `kitchen-chef-infra-agentless`.

**Acceptance criteria:**
- [ ] Existing non-agentless kitchen.yml files work unchanged
- [ ] All Waves 1-14 agentless code removed from TKE core
- [ ] `bundle exec rake test` passes on TKE core after cleanup

---

### Wave 1 Summary

| Story | Track | Parallel? | Depends On |
|-------|-------|-----------|------------|
| CHEF-36823 | A | — | Nothing (foundation) |
| CHEF-34610 | A | With CHEF-36823 (same codebase) | CHEF-36823 (co-developed) |
| CHEF-27348 | B | ✅ Yes — parallel with Track A | Nothing (TKE core, separate repo) |

---

## Wave 2: Credential System + Source Lifecycle

> **Goal:** Build the credential manager (provision/cleanup/mask/warn) and implement `kitchen create` for the agentless-source node. After this wave, `kitchen create` should spin up a source node.

### Track A — Credential System

#### CHEF-27354 · CredentialManager: Per-Operation Ephemeral Lifecycle

**What to build:**
- `Kitchen::Agentless::CredentialManager` class
- `#provision(instance_name)` — upload credentials to source node
- `#cleanup(instance_name)` — delete credentials from source node
- `ensure` block pattern — cleanup runs even on exception
- Parse `kitchen-agentless-credentials.yml` format (inline, credential-file, databag types)
- **Per-instance credential isolation:** Write to `/tmp/kitchen-agentless-<instance-name>/` on source to avoid conflicts with `kitchen -c N`

**Key deliverable:** `lib/kitchen/agentless/credential_manager.rb`

**Acceptance criteria:**
- [ ] Credentials provisioned at start of operation
- [ ] Credentials deleted after operation (success AND failure)
- [ ] Per-instance isolation — no conflicts with parallel runs
- [ ] All 3 credential types parsed correctly

---

#### CHEF-27346 · Mask Secrets + Warn on Insecure Handling (parallel with CHEF-27354)

**What to build:**
- OWASP warning before first credential use: `"You are accessing a plaintext secret..."`
- Post-run warning for `pass-cmd-line` mode: `"Warning: credentials may remain in shell history..."`
- Secret masking in TKE logger output (mask values from credentials file)
- Warnings trigger at **both** converge AND verify

**Tight coupling:** Uses `CredentialManager` — can be built as methods within the same class or as a mixin. Develop in parallel with CHEF-27354.

**Acceptance criteria:**
- [ ] OWASP warning on plaintext credentials before use
- [ ] Shell history warning when `pass-cmd-line` mode used
- [ ] Credential values masked in all logged output
- [ ] Warnings fire during both converge and verify

---

#### CHEF-27355 · Passphrase on Credentials File (parallel with CHEF-27354)

**What to build:**
- `credential-file` type with optional `passphrase:` field
- Encrypted credentials file decrypted on source before use
- Passphrase supports ERB: `<%= ENV['CRED_PASSPHRASE'] %>`

**Acceptance criteria:**
- [ ] `credential-file` type with passphrase decrypts correctly
- [ ] Missing passphrase on encrypted file → clear error
- [ ] ERB in passphrase field evaluates correctly

---

### Track B — Source Lifecycle

#### CHEF-27350 · Source Node Creation (`kitchen create` Flow)

**What to build:**
- `AgentlessDriver#create` — spin up agentless-source node:
  - Resolve source config: `driver.agentless.source_node.driver:` → `driver:` top-level
  - Delegate to `sub_driver.create(source_state)` via `AgentlessSource` adapter
  - Persist source state to `.kitchen/agentless-source.yml`
  - **File lock** around source creation (from CHEF-36823 design)
- `AgentlessDriver#create` — create target instances:
  - Resolve per-target config via inheritance chain
  - Delegate to `sub_driver.create(target_state)`
  - For `volatility: real` — register targets in state only (no VM creation)
- Provisioner `#prepare_command` — upload cookbook sandbox to source via transport

**Acceptance criteria:**
- [ ] `kitchen create` spins up source + targets (ephemeral)
- [ ] `kitchen create` spins up source only (real mode)
- [ ] Source state persisted to `.kitchen/agentless-source.yml`
- [ ] File lock prevents double source creation with `-c N`
- [ ] Cookbook sandbox uploaded to source node

---

### Wave 2 Summary

| Story | Track | Parallel? | Depends On |
|-------|-------|-----------|------------|
| CHEF-27354 | A | — | Wave 1 (Config, RemoteNode) |
| CHEF-27346 | A | ✅ With CHEF-27354 | Wave 1 |
| CHEF-27355 | A | ✅ With CHEF-27354 | Wave 1 |
| CHEF-27350 | B | ✅ With Track A | Wave 1 (AgentlessDriver) |

---

## Wave 3: Provisioner + Sub-Drivers

> **Goal:** Implement the full converge flow end-to-end. After this wave, `kitchen converge` should work with at least one sub-driver (EC2 or Docker).

### Track A — Provisioner

#### CHEF-27349 · Provisioner Rewrite: `ChefInfraAgentless`

**What to build:**
- Rewrite `Kitchen::Provisioner::ChefInfraAgentless`:
  - `#prepare_command` — install CIC 19+ on source (native package, cached)
  - `#run_command` — construct + execute `chef-client --target <protocol>://<endpoint>` on source
  - `#cleanup_command` — delete credentials via `CredentialManager#cleanup` (ensure block)
- Chef 19+ hard validation: `UserError` if `version < 19`
- Local mode: use system calls instead of SSH transport to source
- **Cross-plugin config access:** Provisioner reads `driver.agentless:` config via `instance.driver` reference (TK instances hold refs to all plugin objects)

**Acceptance criteria:**
- [ ] CIC installed on source (skipped if already correct version)
- [ ] `chef-client --target ssh://...` executed on source
- [ ] Credentials provisioned before and cleaned after (ensure block)
- [ ] Chef < 19 → UserError
- [ ] Local mode → system calls, version setting ignored with warning

---

#### CHEF-27353 · Result Collection + Output Streaming (parallel with CHEF-27349)

**What to build:**
- Stream `chef-client --target` stdout/stderr from source to TKE logger
- Mask credential values in output before logging
- Capture exit code and map to TK action status (converged / failed)
- Handle connection drops gracefully (SSH timeout → retry or clear error)

**Acceptance criteria:**
- [ ] Real-time output streaming to TKE logger
- [ ] Secrets masked in all output lines
- [ ] Non-zero exit → `ActionFailed` with meaningful message
- [ ] SSH connection drop → clear error with retry guidance

---

### Track B — Sub-Driver Integrations

#### CHEF-36824 · EC2 + Docker Sub-Driver Integrations (parallel with Track A)

**What to build:**

*EC2:*
- `sub_driver: ec2` integration with kitchen-ec2
- `kitchen create` → launch source EC2 + target EC2 instances
- `kitchen destroy` → terminate all instances
- State: persist `server_id` + endpoint per node
- End-to-end smoke test: create → converge → verify → destroy

*Docker:*
- `sub_driver: docker` integration with kitchen-docker
- Source container: `chef/agentless-source:<cic-version>` (SSH-enabled)
- Target containers: `chef/agentless-target-<platform>` (SSH-enabled)
- `kitchen create` → spin up source + target containers with SSH exposed
- `kitchen destroy` → tear down all containers
- End-to-end smoke test: create → converge → verify → destroy

**External dependency:** Docker SSH images must be available. If not yet published, mock with manually built images for testing.

**Acceptance criteria:**
- [ ] EC2: full lifecycle works end-to-end
- [ ] Docker: full lifecycle works end-to-end
- [ ] State files correctly track source + targets
- [ ] Sub-driver config inheritance resolves correctly

---

### Wave 3 Summary

| Story | Track | Parallel? | Depends On |
|-------|-------|-----------|------------|
| CHEF-27349 | A | — | Wave 2 (CredentialManager, source lifecycle) |
| CHEF-27353 | A | ✅ With CHEF-27349 | Wave 2 (source transport) |
| CHEF-36824 | B | ✅ With Track A | Wave 1 (superdriver), Wave 2 (source lifecycle) |

---

## Wave 4: Verifier + Mode-Specific Converge

> **Goal:** Add `kitchen verify` support and validate both real and container mode converge. After this wave, the full `kitchen test` workflow works.

### Track A — InSpec Verifier

#### CHEF-36825 · InSpec Verifier: `Kitchen::Verifier::InspecAgentless`

**What to build:**
- `Kitchen::Verifier::InspecAgentless`:
  - `#prepare_command` — install InSpec 5+ as full package on source (cached)
  - `#run_command` — `inspec exec <profile> --target <protocol>://<endpoint>` on source
  - `#cleanup_command` — delete credentials (ensure block, same as provisioner)
- Credential lifecycle identical to provisioner (reuses `CredentialManager`)
- Local mode: run InSpec from workstation directly
- Compliance Phase (InSpec embedded in CIC): transparent — no extra handling

**Acceptance criteria:**
- [ ] InSpec installed on source (skipped if correct version)
- [ ] `inspec exec --target` runs on source, output streamed
- [ ] Credentials provisioned/cleaned per-verify
- [ ] Local mode → system inspec call
- [ ] `kitchen test` (create → converge → verify → destroy) works end-to-end

---

### Track B — Mode-Specific Converge Validation

#### CHEF-27351 · Real Mode Converge (`volatility: real`) (parallel with Track A)

**What to build:**
- Validate converge works against pre-existing targets
- `transport.hostname` required in real mode — clear error if missing
- Source node created; targets registered in state with hostnames from config
- `chef-client --target` runs against real endpoints
- `kitchen destroy` clears state only (does NOT terminate real nodes)

**Acceptance criteria:**
- [ ] Converge against pre-existing target nodes works
- [ ] Missing `hostname` in real mode → UserError
- [ ] `kitchen destroy` removes state without terminating real targets
- [ ] Source node destroyed on `kitchen destroy`

---

#### CHEF-27352 · Container Mode Converge (`sub_driver: docker`) (parallel with Track A)

**What to build:**
- Validate converge works with Docker containers as targets
- SSH-enabled images used (not Docker exec)
- `chef-client --target ssh://<container-ip>` from source container
- Container networking: source can reach targets via Docker network
- Handle Docker-specific edge cases (container restart, port conflicts)

**Acceptance criteria:**
- [ ] Converge against Docker containers works via real SSH
- [ ] Source-to-target SSH connectivity verified
- [ ] Container cleanup on destroy is complete
- [ ] Port conflicts handled with clear error

---

### Wave 4 Summary

| Story | Track | Parallel? | Depends On |
|-------|-------|-----------|------------|
| CHEF-36825 | A | — | Wave 2 (CredentialManager), Wave 3 (sub-drivers) |
| CHEF-27351 | B | ✅ With Track A | Wave 3 (provisioner + EC2 sub-driver) |
| CHEF-27352 | B | ✅ With Track A | Wave 3 (provisioner + Docker sub-driver) |

---

## Wave 5: Advanced Features + UX

> **Goal:** Polish error handling, add ERB support, implement destroy flags and kitchen list enhancements. After this wave, all UX features are complete.

### Track A — Error Handling + ERB

#### CHEF-27347 · Error Handling for Unsupported Resources

**What to build:**
- Chef version < 19 → `UserError: "chef_infra_agentless requires Chef Infra Client 19+"`
- Array `remote_nodes` → `UserError` with migration instructions
- `driver:` key in real-mode remote_node → `UserError`
- `version:` in local mode → warning (not error)
- `agentless-source` reserved name collision → `UserError`
- Sub-driver gem not installed → `UserError` with install instructions

**Note:** Many of these validations are implemented in earlier waves (Config class, provisioner). This story is about **reviewing completeness** and adding any missing error paths.

**Acceptance criteria:**
- [ ] All 6 error scenarios produce clear, actionable UserError messages
- [ ] No raw Ruby exceptions (LoadError, NoMethodError, etc.) reach the user

---

#### CHEF-34937 · ERB Dynamic Target Lists (parallel with CHEF-27347)

**What to build:**
- Validate ERB works in `driver.agentless.remote_nodes:` (already supported by TK)
- Test ERB in `source_node:` overrides
- Document ERB patterns for agentless config

**Acceptance criteria:**
- [ ] ERB in `remote_nodes` hostnames evaluates correctly
- [ ] ERB in `source_node` driver/transport config works
- [ ] ERB errors produce clear messages (not raw Ruby traces)

---

### Track B — Lifecycle UX

#### CHEF-36826 · Lifecycle UX: Destroy Behaviours + Kitchen List

**What to build:**

*`--keep-agentless-source` flag (TKE core):*
- Add `--keep-agentless-source` boolean flag to `kitchen destroy`
- Default `false` — destroy source + all targets
- When `true` — destroy targets only; keep source running
- **Implementation approach:** TKE core adds a generic `--keep-source` driver option; `AgentlessDriver` reads it. Keeps TKE core generic.

*Block destroy-source (KCAI):*
- `AgentlessDriver#destroy` checks for running targets when destroying source
- Running targets → `UserError` with helpful message
- Hard block — no `--force`

*`kitchen list` source section (TKE core):*
- Add `Agentless Source` section above target instances
- Columns: Instance | Driver | State | Endpoint | CIC Ver | InSpec Ver
- **Implementation approach:** Driver exposes a `#source_info` method; `list.rb` calls it if available. Keeps TKE core generic.
- Hidden when `source_node.mode: local` or driver is not agentless

**Acceptance criteria:**
- [ ] `kitchen destroy` tears down everything (default)
- [ ] `kitchen destroy --keep-agentless-source` keeps source, destroys targets
- [ ] `kitchen destroy agentless-source` blocked when targets exist
- [ ] `kitchen list` shows Agentless Source section with correct columns
- [ ] Source section hidden in local mode

---

### Wave 5 Summary

| Story | Track | Parallel? | Depends On |
|-------|-------|-----------|------------|
| CHEF-27347 | A | — | Waves 1-4 (review all error paths) |
| CHEF-34937 | A | ✅ With CHEF-27347 | Wave 1 (Config parsing) |
| CHEF-36826 | B | ✅ With Track A | Wave 3 (sub-drivers), Wave 4 (verifier for version columns) |

---

## Wave 6: Documentation + QA

> **Goal:** Complete documentation and Qmetry test cases. After this wave, the epic is done.

#### CHEF-27345 · Documentation

**What to build:**
- Full documentation rewrite covering:
  - kitchen.yml format — 4 example configurations
  - `kitchen-agentless-credentials.yml` format and credential types
  - `kitchen list` output with Agentless Source section
  - `kitchen destroy` variants (`--keep-agentless-source`, blocking rules)
  - Local mode usage
  - Plugin naming convention
  - InSpec verifier usage
  - Troubleshooting guide

**Acceptance criteria:**
- [ ] All 4 kitchen.yml variants documented with working examples
- [ ] Credential file format documented with all 3 types
- [ ] All destroy behaviours documented
- [ ] Local mode documented

---

#### CHEF-34938 · Qmetry Test Cases (parallel with CHEF-27345)

**What to build:**
- Qmetry test cases covering all 19 stories
- Coverage for: InSpec verifier, Docker mode, local mode, `--keep-agentless-source`, `kitchen list` source section, WinRM, ERB, error handling

**Acceptance criteria:**
- [ ] Test cases created for all acceptance criteria across all stories
- [ ] Test cases linked to Jira stories

---

### Deferred / Floating Story

#### CHEF-34939 · WinRM / Windows Targets

**When to start:** Can begin from **Wave 4 onwards** (needs provisioner + sub-drivers)
**Why floating:** Windows support is important but doesn't block the Linux/SSH MVP. Can be developed in parallel with any Wave 4-6 story by a separate developer.

**What to build:**
- WinRM transport config resolution via new driver config inheritance
- `chef-client --target winrm://...` execution
- Windows Docker containers (`chef/agentless-target-windows-2025`) — **deferred if images not ready**
- InSpec `--target winrm://...` for verify

**Acceptance criteria:**
- [ ] WinRM converge works against Windows target
- [ ] WinRM verify works against Windows target
- [ ] Transport config resolves correctly for WinRM

---

## Parallel Execution Matrix

```
Wave    Track A                          Track B                         Notes
────    ───────                          ───────                         ─────
  1     CHEF-36823 + CHEF-34610          CHEF-27348                      2 developers
        (Superdriver + Assignment)       (Backward compat — TKE core)
        ────────────────────────────────────────────────────────────────
  2     CHEF-27354 + 27346 + 27355       CHEF-27350                      2 developers
        (Credential system)              (Source lifecycle)
        ────────────────────────────────────────────────────────────────
  3     CHEF-27349 + CHEF-27353          CHEF-36824                      2 developers
        (Provisioner + output)           (EC2 + Docker sub-drivers)
        ────────────────────────────────────────────────────────────────
  4     CHEF-36825                       CHEF-27351 + CHEF-27352         2 developers
        (InSpec verifier)                (Real + Container mode)
        ────────────────────────────────────────────────────────────────
  5     CHEF-27347 + CHEF-34937          CHEF-36826                      2 developers
        (Errors + ERB)                   (Lifecycle UX)
        ────────────────────────────────────────────────────────────────
  6     CHEF-27345                       CHEF-34938                      2 developers
        (Documentation)                  (Qmetry)

Floating: CHEF-34939 (WinRM) — any developer, Wave 4+
```

---

## Critical Path

The critical path (longest sequential chain) is:

```
CHEF-36823 → CHEF-27354 → CHEF-27349 → CHEF-36825 → CHEF-36826 → CHEF-27345
(Superdriver) (CredMgr)    (Provisioner) (Verifier)   (UX)         (Docs)
   Wave 1      Wave 2        Wave 3       Wave 4      Wave 5       Wave 6
```

Everything else can be parallelized alongside this chain.

---

## Architecture Decisions Incorporated

The following architectural concerns (raised during review) are addressed in this wave plan:

| Concern | Resolution | Addressed In |
|---------|-----------|--------------|
| **Race condition with `-c N`** | File lock around source creation | CHEF-36823 (Wave 1) |
| **Credential conflicts during parallel runs** | Per-instance isolation: `/tmp/kitchen-agentless-<instance>/` | CHEF-27354 (Wave 2) |
| **TKE core coupling (`--keep-source`, `kitchen list`)** | Generic driver hooks (`#source_info`, `--keep-source` option) — TKE stays generic | CHEF-36826 (Wave 5) |
| **Cross-plugin config access** | Provisioner/verifier access driver config via `instance.driver` reference | CHEF-27349 (Wave 3) |
| **TKE core cleanup (Waves 1-14 code)** | Explicit scope in CHEF-27348 | CHEF-27348 (Wave 1) |
| **`kitchen test` workflow** | Validated in CHEF-36825 (verifier story) as end-to-end AC | CHEF-36825 (Wave 4) |
| **Sub-driver gem missing** | Explicit `UserError` with install instructions | CHEF-27347 (Wave 5) |

---

## Development Workflow Rules

These rules apply to **every story** in every wave without exception.

### Branch Strategy

| Rule | Detail |
|------|--------|
| **Base branch** | All feature branches are checked out from `agentless-dev-latest` |
| **PR target** | All PRs must target `agentless-dev-latest` (never `main` directly) |
| **Branch naming** | `<JIRA-KEY>` — e.g. `CHEF-36823`, `CHEF-27349` |
| **Merge to main** | Only `agentless-dev-latest` is merged to `main` after epic completion |

```bash
# Starting any story — always from agentless-dev-latest
git fetch origin
git checkout agentless-dev-latest
git pull origin agentless-dev-latest
git checkout -b CHEF-XXXXX
```

### PR Requirements

Every PR must have:
- [ ] **`ai-assisted` label** — applied to every PR without exception
- [ ] Target branch set to `agentless-dev-latest`
- [ ] Jira key in title: `CHEF-XXXXX: <description>`
- [ ] DCO signoff on all commits (`git commit --signoff`)
- [ ] Tests passing with >80% coverage

```bash
# Creating a PR (always targeting agentless-dev-latest)
gh pr create   --base agentless-dev-latest   --title "CHEF-XXXXX: description"   --label "ai-assisted"   --body "..."
```

### TKE Core Change Policy

Changes to `chef-test-kitchen-enterprise` (TKE core) must be **minimal**. The only permitted TKE core changes across the entire epic are:

| File | Permitted Change | Story |
|------|-----------------|-------|
| `lib/kitchen/command/list.rb` | Add generic `driver.source_info` hook rendering | CHEF-36826 |
| `lib/kitchen/command/destroy.rb` | Add generic `--driver-option` passthrough | CHEF-36826 |
| `lib/kitchen/agentless/` (delete all) | Remove all Waves 1–14 agentless code | CHEF-27348 |
| `lib/kitchen/provisioner/base.rb` | Remove `#agentless_mode?` + `default_config :agentless` | CHEF-27348 |

> ⛔ **No other TKE core files should be touched.** All agentless logic lives in `kitchen-chef-infra-agentless`. If you find yourself editing TKE core beyond the list above, stop and reassess — the architecture provides a plugin hook for it.

---

## Pre-Implementation Checklist

Before starting Wave 1:

- [ ] `agentless-dev-latest` branch exists on both repos (`kitchen-chef-infra-agentless` + `chef-test-kitchen-enterprise`)
- [ ] `ai-assisted` label exists on both repos in GitHub
- [ ] Confirm `kitchen-chef-infra-agentless` repo access
- [ ] Verify Docker SSH images availability (or plan to build mock images for testing)
- [ ] Verify kitchen-ec2 and kitchen-docker gem versions to target
- [ ] Confirm Chef Infra Client 19 availability for testing

---

*Wave plan v2 — 2026-07-13*
*19 active stories across 6 waves with 2 parallel tracks per wave*
*Updated: branch strategy, PR rules, TKE core change policy*
