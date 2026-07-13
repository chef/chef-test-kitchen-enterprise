# CHEF-23408 — Agentless Mode for TKE: Architecture v3

> **Status:** Updated — implementation review findings incorporated (2026-07-10)
> **Previous version:** v2 (2026-07-07) — product team answers incorporated
> **Previous implementation:** Waves 1–14 in session `c2eb2974-b64a-474e-9012-e589d700ff2c`
> **Target repo:** `chef/kitchen-chef-infra-agentless` (existing private repo, expanded)

---

## Table of Contents

1. [What Changed From Waves 1–14](#1-what-changed-from-waves-114)
2. [Core Design Principles](#2-core-design-principles)
3. [Repository & Packaging Model](#3-repository--packaging-model)
4. [kitchen.yml Format](#4-kitchenyml-format)
   - 4.1 [EC2 Ephemeral Targets](#41-ec2-ephemeral-targets)
   - 4.2 [EC2 Real (Pre-existing) Targets](#42-ec2-real-pre-existing-targets)
   - 4.3 [Docker Ephemeral Targets](#43-docker-ephemeral-targets)
   - 4.4 [Local Mode (EC2 Targets)](#44-local-mode-ec2-targets)
   - 4.5 [Local Mode (Docker Targets)](#45-local-mode-docker-targets)
5. [Instance Model & `kitchen list`](#5-instance-model--kitchen-list)
6. [Superdriver Architecture](#6-superdriver-architecture)
   - 6.1 [Concurrency Safety](#61-concurrency-safety)
7. [Plugin Naming Convention](#7-plugin-naming-convention)
8. [Provisioner: ChefInfraAgentless](#8-provisioner-chefinfraagentless)
   - 8.1 [Cross-Plugin Config Access](#81-cross-plugin-config-access)
9. [Verifier: InspecAgentless](#9-verifier-inspecagentless)
10. [Local Mode](#10-local-mode)
11. [Credential Lifecycle](#11-credential-lifecycle)
    - 11.1 [Credential Isolation with Parallel Runs](#111-credential-isolation-with-parallel-runs)
12. [Command Semantics](#12-command-semantics)
    - 12.1 [kitchen create](#121-kitchen-create)
    - 12.2 [kitchen converge](#122-kitchen-converge)
    - 12.3 [kitchen verify](#123-kitchen-verify)
    - 12.4 [kitchen destroy](#124-kitchen-destroy)
    - 12.5 [kitchen test](#125-kitchen-test)
13. [TKE Core Integration](#13-tke-core-integration)
14. [Target Assignment Model](#14-target-assignment-model)
15. [Volatility: Ephemeral vs Real](#15-volatility-ephemeral-vs-real)
16. [Docker SSH Images](#16-docker-ssh-images)
17. [Sequence Diagrams](#17-sequence-diagrams)
18. [Component Reference](#18-component-reference)
19. [Story Review: Old vs New](#19-story-review-old-vs-new)
    - 19.1 [Stories Still Valid (scope changes)](#191-stories-still-valid-scope-changes)
    - 19.2 [Stories That Need Significant Rework](#192-stories-that-need-significant-rework)
    - 19.3 [Stories No Longer Needed](#193-stories-no-longer-needed)
    - 19.4 [New Stories Required](#194-new-stories-required)
20. [Decision Log](#20-decision-log)

---

## 1. What Changed From Waves 1–14

| Concern | Waves 1–14 | Architecture v3 |
|---|---|---|
| **`agentless:` location in kitchen.yml** | Under `provisioner:` | **Inside `driver:`** — driver owns all node lifecycle |
| **Driver** | `dokken` / `ec2` directly | New `agentless` superdriver with `sub_driver:` |
| **InSpec** | Out of scope | **In scope** — `Kitchen::Verifier::InspecAgentless` in same repo |
| **Local mode** | `source.mode: local` (ad-hoc) | `source_node.mode: local` inside `driver.agentless.source_node:` — handled internally by `AgentlessDriver`, no separate driver class |
| **Repo** | `kitchen-chef-enterprise` + TKE core | **`kitchen-chef-infra-agentless` only** (driver + provisioner + verifier all here) |
| **Credential lifecycle** | Delete on `kitchen destroy` | **Delete after every converge AND verify** (ensure blocks) |
| **Parallel runs (`-c N`)** | Not addressed | **File lock** on source creation; per-instance credential paths on source |
| **TKE core coupling** | Agentless-specific code in TKE core | **Generic driver hooks** (`#source_info`, `--keep-source` option) — TKE stays agentless-unaware |
| **Cross-plugin config** | Not addressed | Provisioner/verifier access driver config via `instance.driver` reference |
| **`kitchen test`** | Not addressed | Full `create → converge → verify → destroy` flow documented explicitly |
| **Windows Docker MVP** | In scope | **Deferred** — Windows containers require Hyper-V isolation; Linux targets only for MVP |
| **Chef version** | Any | **19+ only** |
| **Container driver** | Dokken (Docker exec, no SSH) | **kitchen-docker** with SSH-enabled images (Chef-published) |
| **EC2** | Future | **Required for MVP** — must prove driver generality |
| **`agentless-source` in `kitchen list`** | Mixed into instance table | **Separate section** |
| **`kitchen destroy agentless-source` with live targets** | Allowed | **Blocked** — raises error |
| **Packaging** | Open gem | **Private premium gem** in existing `kitchen-chef-infra-agentless` repo |

---

## 2. Core Design Principles

1. **`agentless:` config belongs to the driver.** The driver makes all decisions about what nodes exist, how to create them, and how to connect to them. Agentless config naturally lives under `driver:`.
2. **The instance IS the target.** `kitchen list` shows one row per target node. `agentless-source` is shown in a separate section.
3. **Superdriver wraps sub-drivers.** `agentless` delegates actual VM/container creation to `sub_driver:` (`ec2`, `docker`). Architecture is generic — not coupled to any one provider. Local mode is a property of `source_node.mode: local` and is handled internally; the `sub_driver` still manages target nodes.
4. **Credentials are ephemeral per-operation.** Provisioned at the start of each converge/verify. Deleted at the end — even on failure (rescue block).
5. **Two sub-drivers prove generality for MVP: Docker + EC2.**
6. **Single repo, all components.** Driver, provisioner, and verifier all live in `kitchen-chef-infra-agentless`. Separation into multiple gems is a future concern.

---

## 3. Repository & Packaging Model

### Target Repo: `chef/kitchen-chef-infra-agentless` (existing private repo)

All new code goes into this one repo. Existing provisioner code from Waves 1–14 is **removed** and replaced.

```
kitchen-chef-infra-agentless/
├── lib/
│   └── kitchen/
│       ├── driver/
│       │   ├── agentless.rb              # NEW: superdriver (Kitchen::Driver::Agentless)
│       │   └── agentless_source.rb       # NEW: source node adapter
│       ├── provisioner/
│       │   └── chef_infra_agentless.rb   # REWRITE: Chef Infra Client 19+ on source
│       ├── verifier/
│       │   └── inspec_agentless.rb       # NEW: InSpec on source (Kitchen::Verifier::InspecAgentless)
│       └── agentless/
│           ├── config.rb                 # NEW: parses driver.agentless: block
│           ├── remote_node.rb            # NEW: value object for a single target
│           └── credential_manager.rb     # NEW: provisions/deletes credentials on source
├── spec/
│   └── kitchen/
│       ├── driver/
│       ├── provisioner/
│       └── verifier/
└── kitchen-chef-infra-agentless.gemspec
```

### TKE Core (`chef-test-kitchen-enterprise`) — Minimal Changes Only

| File | Change |
|---|---|
| `lib/kitchen/command/list.rb` | Add generic `driver.source_info` hook rendering (agentless-unaware) |
| `lib/kitchen/command/destroy.rb` | Add generic `--driver-option` passthrough |
| `lib/kitchen/agentless/` (delete) | Remove all Waves 1–14 agentless code |
| `lib/kitchen/provisioner/base.rb` | Remove `#agentless_mode?` + `default_config :agentless` |

> **All agentless logic stays in `kitchen-chef-infra-agentless`.** TKE core remains generic. No other TKE core files should be modified across this entire epic.

---

### 3.1 Development Workflow

These rules apply to every story in every wave.

#### Branch Strategy

- **Base branch:** `agentless-dev-latest` on both repos
- **Feature branches:** always checked out from `agentless-dev-latest`
- **PR target:** all PRs merge into `agentless-dev-latest` (never directly to `main`)
- **Branch naming convention:** `<JIRA-KEY>` — e.g. `CHEF-36823`

```bash
git fetch origin
git checkout agentless-dev-latest
git pull origin agentless-dev-latest
git checkout -b CHEF-XXXXX
```

#### PR Requirements

Every PR must have:
- **`ai-assisted` label** applied (no exceptions)
- Title formatted as: `CHEF-XXXXX: <short description>`
- Base branch explicitly set to `agentless-dev-latest`
- DCO signoff on all commits (`git commit --signoff`)
- Tests passing, coverage >80%

```bash
gh pr create   --base agentless-dev-latest   --title "CHEF-XXXXX: description"   --label "ai-assisted"   --body "..."
```

#### TKE Core Change Policy

Changes to `chef-test-kitchen-enterprise` must be minimal. Only the four files listed in the table above may be touched across the entire epic. Everything else — all agentless logic, config parsing, lifecycle management, credentials — lives exclusively in `kitchen-chef-infra-agentless`.

### Future / Out of Scope Now
- Splitting verifier into a separate `kitchen-inspec-agentless` gem — post-MVP decision

---

## 4. kitchen.yml Format

> ⚠️ **Key structural change from Waves 1–14:** The `agentless:` block now lives **inside `driver:`**, not under `provisioner:`. The driver owns all node lifecycle decisions.

### 4.1 EC2 Ephemeral Targets

```yaml
driver:
  name: agentless           # Kitchen::Driver::Agentless
  sub_driver: ec2           # delegates to kitchen-ec2 for VM creation
  region: us-east-1         # sub_driver settings — apply to all nodes unless overridden

  agentless:
    volatility: ephemeral   # TKE creates and destroys all nodes
    credential-map-file: test/kitchen-agentless-credentials.yml
    credential-passing-mode: pass-by-env-var  # | pass-cmd-line | pass-by-creds-file

    source_node:
      # Overrides applied only to the agentless-source node (on top of driver: defaults)
      driver:
        image_id: ami-020cba7c55df1f615   # Source AMI — needs chef-client-capable base
      transport:
        username: ubuntu
        ssh_key: ~/.ssh/source-key.pem

    remote_nodes:
      # Hash keyed by exact instance name (<suite>-<platform>)
      default-ubuntu-2204:
        driver:
          image_id: ami-0c94855ba95b798e7
        transport:
          username: ubuntu
          ssh_key: test/target-key.pem
      mysuite-windows-2025:
        driver:
          image_id: ami-0abcdef1234567890
        transport:
          name: winrm
          username: Administrator
          password: "<%= ENV['WIN_PASS'] %>"

provisioner:
  name: chef_infra_agentless     # Kitchen::Provisioner::ChefInfraAgentless
  version: 19.1.2                # Chef Infra Client 19+ only

verifier:
  name: inspec_agentless         # Kitchen::Verifier::InspecAgentless
  version: 5.22.0                # Optional — defaults to latest InSpec 5+

platforms:
  - name: ubuntu-2204
    driver:
      image_id: ami-0c94855ba95b798e7   # Default target AMI for all ubuntu-2204 instances
    transport:
      username: ubuntu
      ssh_key: ~/.ssh/id_rsa

suites:
  - name: default
    run_list:
      - recipe[my_cookbook::default]
  - name: mysuite
    run_list:
      - recipe[my_cookbook::web]
```

### 4.2 EC2 Real (Pre-existing) Targets

```yaml
driver:
  name: agentless
  sub_driver: ec2
  region: us-east-1

  agentless:
    volatility: real          # TKE tracks but does NOT create/destroy target nodes
    credential-map-file: test/kitchen-agentless-credentials.yml
    credential-passing-mode: pass-cmd-line

    source_node:
      driver:
        image_id: ami-020cba7c55df1f615
      transport:
        username: ubuntu
        ssh_key: ~/.ssh/source-key.pem

    remote_nodes:
      default-ubuntu-2204:
        # driver: NOT PERMITTED under volatility: real — raises UserError
        transport:
          hostname: ecommerce1.myco.com    # REQUIRED under real mode
          username: ubuntu
          ssh_key: test/node-specific-key.pem
      default-windows-2025:
        transport:
          name: winrm
          hostname: win-edge-01.myco.com
          username: Administrator
          password: "<%= ENV['WIN_PASS'] %>"

provisioner:
  name: chef_infra_agentless
  version: 19.1.2

verifier:
  name: inspec_agentless

platforms:
  - name: ubuntu-2204
  - name: windows-2025

suites:
  - name: default
```

### 4.3 Docker Ephemeral Targets

```yaml
driver:
  name: agentless
  sub_driver: docker          # delegates to kitchen-docker (NOT kitchen-dokken)
                              # kitchen-docker uses SSH; Dokken uses Docker exec (incompatible)

  agentless:
    volatility: ephemeral
    credential-map-file: test/kitchen-agentless-credentials.yml
    credential-passing-mode: pass-by-env-var

    source_node:
      driver:
        image: chef/agentless-source:19   # Chef-published image: chef-client 19 + SSH
      transport:
        username: root

    remote_nodes:
      default-ubuntu-2204:
        driver:
          image: chef/agentless-target-ubuntu-2204   # Chef-published SSH-enabled target image
        transport:
          username: root
      default-windows-2025:
        driver:
          image: chef/agentless-target-windows-2025  # Chef-published WinRM-enabled target image
        transport:
          name: winrm
          username: Administrator

provisioner:
  name: chef_infra_agentless
  version: 19.1.2

verifier:
  name: inspec_agentless

platforms:
  - name: ubuntu-2204
  - name: windows-2025

suites:
  - name: default
```

> **Why kitchen-docker over kitchen-dokken?**
> Dokken communicates via Docker exec — there is no network stack or SSH daemon in the container.
> Agentless mode requires `chef-client --target ssh://...` (real SSH between source and target).
> kitchen-docker creates containers that expose a real SSH port, which matches this requirement.
> SSH-enabled images are maintained by Chef (see [§15 Docker SSH Images](#15-docker-ssh-images)).

### 4.4 Local Mode (EC2 Targets)

```yaml
driver:
  name: agentless
  sub_driver: ec2             # Still used to create/destroy ephemeral TARGET nodes
  region: us-east-1

  agentless:
    volatility: ephemeral     # Targets are created/destroyed by sub_driver as normal
    credential-map-file: test/kitchen-agentless-credentials.yml

    source_node:
      mode: local             # ← workstation IS the source; no source VM is created
      # No driver: or transport: needed here

    remote_nodes:
      default-ubuntu-2204:
        driver:
          image_id: ami-0c94855ba95b798e7
        transport:
          username: ubuntu
          ssh_key: test/target-key.pem

provisioner:
  name: chef_infra_agentless
  # version: NOT SETTABLE in local mode
  # TKE warns and ignores: "Ignoring version request in local mode"

verifier:
  name: inspec_agentless
  # version: NOT SETTABLE in local mode

platforms:
  - name: ubuntu-2204

suites:
  - name: default
```

> **Local mode behaviour:**
> - `source_node.mode: local` tells `AgentlessDriver` to skip source VM creation entirely. The workstation runs `chef-client` and `inspec` directly.
> - `sub_driver:` still applies to ephemeral **target** nodes — they are created/destroyed normally.
> - `chef-client` must be in PATH (or Chef Workstation installed).
> - `version:` under provisioner or verifier is ignored with a warning: `"Ignoring version request in local mode"`.
> - Local mode applies to both provisioner and verifier together — you cannot use it for only one.
> - No `agentless-source` section appears in `kitchen list` (workstation is the source).

### 4.5 Local Mode (Docker Targets)

This is the **primary developer workflow**: workstation as source (no source VM cost), ephemeral Docker containers as targets. Chef Workstation must be installed locally.

```yaml
driver:
  name: agentless
  sub_driver: docker          # Creates/destroys target containers

  agentless:
    volatility: ephemeral     # Target containers are created/destroyed normally
    credential-map-file: test/kitchen-agentless-credentials.yml
    credential-passing-mode: pass-by-env-var

    source_node:
      mode: local             # Workstation is the source — no source container
      # No driver: or transport: block needed

    remote_nodes:
      default-ubuntu-2204:
        driver:
          image: chef/agentless-target-ubuntu-2204   # SSH-enabled target image
        transport:
          username: root
      default-ubuntu-2404:
        driver:
          image: chef/agentless-target-ubuntu-2404
        transport:
          username: root

provisioner:
  name: chef_infra_agentless
  # version: not settable — uses local chef-client installation

verifier:
  name: inspec_agentless
  # version: not settable — uses local inspec installation

platforms:
  - name: ubuntu-2204
  - name: ubuntu-2404

suites:
  - name: default
    run_list:
      - recipe[my_cookbook::default]
```

> **Note:** With local mode + Docker targets, `kitchen list` shows only the Target Instances table. The Agentless Source section is omitted. Credentials are written to local `/tmp/kitchen-agentless-<instance>/` and cleaned up via `ensure`.

---

## 5. Instance Model & `kitchen list`

Under the new architecture, `kitchen list` has **two sections**:

```
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│  Agentless Source                                                                            │
├──────────────────────┬────────────────┬──────────┬───────────────┬─────────────┬────────────┤
│  Instance            │  Driver        │  State   │  Endpoint     │  CIC Ver    │  InSpec Ver│
├──────────────────────┼────────────────┼──────────┼───────────────┼─────────────┼────────────┤
│  agentless-source    │  agentless/ec2 │  Running │  10.0.1.5:22  │  19.1.2     │  5.22.0    │
└──────────────────────┴────────────────┴──────────┴───────────────┴─────────────┴────────────┘

┌──────────────────────────────────────────────────────────────────────────────────────┐
│  Target Instances                                                                    │
├──────────────────────┬────────────────┬──────────┬─────────────────┬────────────────┤
│  Instance            │  Driver        │  State   │  Assigned To    │  Last Action   │
├──────────────────────┼────────────────┼──────────┼─────────────────┼────────────────┤
│  default-ubuntu-2204 │  agentless/ec2 │  Running │  10.0.1.10:22   │  Converged     │
│  mysuite-ubuntu-2204 │  agentless/ec2 │  Running │  10.0.1.11:22   │  <Not Created> │
└──────────────────────┴────────────────┴──────────┴─────────────────┴────────────────┘
```

- **`agentless-source` section** — shown only when not in local mode. Columns: Instance, Driver (`agentless/<sub_driver>`), State, Endpoint, CIC Version (installed), InSpec Version (installed). CIC Ver and InSpec Ver show `<not installed>` until the first converge/verify respectively.
- **Target instances section** — shows all suite/platform combos with their assigned target endpoint.
- Under **local mode** — only the target instances section is shown; source section is omitted.

---

## 6. Superdriver Architecture

`Kitchen::Driver::Agentless` is a superdriver that:
1. Reads `driver.agentless:` config
2. Instantiates the real driver for the sub_driver type (`ec2`, `docker`, `local`)
3. Delegates node creation/destruction to the sub-driver with per-node config overrides

```
Kitchen::Driver::Agentless
  │
  ├── config[:sub_driver]  →  Kitchen::Driver.for_plugin("ec2"|"docker"|"local")
  │
  ├── #create(state)   [called once per TARGET instance]
  │     1. Resolve this instance's driver config
  │        (remote_nodes[name].driver overrides platform.driver overrides top-level driver)
  │     2. sub_driver.create(state)      ← creates THIS target VM/container
  │     3. state[:agentless_target] = true
  │     4. If agentless-source not yet created:
  │           source_config = merge(driver:, agentless.source_node.driver:)
  │           source_sub_driver.create(source_state)
  │           persist source_state to .kitchen/agentless-source.yml
  │
  ├── #destroy(state)  [called per instance]
  │     If instance == "agentless-source":
  │       Check: any target instances still running?
  │         YES → raise UserError: "Cannot destroy agentless-source while targets
  │                are still running. Run `kitchen destroy` first, or
  │                `kitchen destroy --keep-agentless-source` to destroy targets only."
  │         NO  → source_sub_driver.destroy(source_state)
  │     Else (target instance):
  │       if --keep-agentless-source flag: skip source destruction
  │       sub_driver.destroy(state)
  │       if last target destroyed && !--keep-agentless-source:
  │         source_sub_driver.destroy(source_state)
  │
  └── Kitchen::Driver::AgentlessSource
        → Thin wrapper around sub_driver with source_node config applied
        → Instance name: "agentless-source"
        → Does NOT appear in suite/platform combos
```

### Config Inheritance (Priority Order, High → Low)

**For each target instance:**
1. `driver.agentless.remote_nodes.<instance-name>.driver:` ← highest
2. `platforms.<platform-name>.driver:`
3. `driver:` top-level (excluding `agentless:` and `sub_driver:` keys)

**For `agentless-source`:**
1. `driver.agentless.source_node.driver:` ← highest
2. `driver:` top-level

**Transport config follows the same resolution order**, replacing `driver:` with `transport:`.

---

### 6.1 Concurrency Safety

`AgentlessDriver#create` is called **once per target instance**. When running `kitchen create -c N` (or `kitchen test -c N`), multiple target creates run concurrently — each may see "source not yet running" and attempt to create it simultaneously. A file lock prevents double source creation.

```
AgentlessDriver#create — source creation with lock
  │
  ├── Acquire exclusive file lock: .kitchen/agentless-source.lock
  │     (blocks until any concurrent creator finishes)
  │
  ├── Re-check: source already running? (re-read .kitchen/agentless-source.yml)
  │     YES → release lock, skip source creation
  │     NO  → create source, write state file, release lock
  │
  └── Proceed with this instance's target creation (concurrent with others — safe)
```

**Key:** Only source creation is serialised. Target creation (one per instance) is fully parallel — no lock needed there.

---

## 7. Plugin Naming Convention

Test Kitchen derives the `name:` value in kitchen.yml from the Ruby class name — **the gem name is independent**. This means the gem can keep its existing name (`kitchen-chef-infra-agentless`) while the driver, provisioner, and verifier classes are named however makes most sense.

The convention is: `Kitchen::<Type>::ClassName` → snake_case of `ClassName`, stripped of the `Kitchen::<Type>::` prefix.

| Ruby Class | `name:` in kitchen.yml | Gem |
|---|---|---|
| `Kitchen::Driver::Agentless` | `agentless` | `kitchen-chef-infra-agentless` |
| `Kitchen::Provisioner::ChefInfraAgentless` | `chef_infra_agentless` | `kitchen-chef-infra-agentless` |
| `Kitchen::Verifier::InspecAgentless` | `inspec_agentless` | `kitchen-chef-infra-agentless` |

The gem name and the plugin `name:` values are fully decoupled. All three plugins ship in the one gem.

---

## 8. Provisioner: ChefInfraAgentless

```
Kitchen::Provisioner::ChefInfraAgentless
  │
  ├── Config validation
  │     → Raises UserError if version < 19 or version missing
  │     → Raises UserError if sub_driver == "local" AND version is set
  │       (with warning: "Ignoring version request in local mode")
  │
  ├── #prepare_command  [runs during kitchen converge — before run_command]
  │     → Install Chef Infra Client <version> on agentless-source via source transport
  │       (native package installer, not gem; skipped if already installed and version matches)
  │     → Provision credentials from kitchen-agentless-credentials.yml onto source
  │     → Issue OWASP warning if plaintext credentials detected:
  │       "You are accessing a plaintext secret, remember not to do this in production!"
  │
  ├── #run_command
  │     → Lookup remote_node for this instance from agentless config
  │     → Construct: chef-client --target <protocol>://<hostname>:<port>
  │                              [--key <ssh-key>] [--user <username>]
  │                              [--cookbook-path ...]
  │     → Execute on agentless-source via source transport
  │     → Stream output back to TKE logger
  │     → Mask any credential values in output before logging
  │
  └── #cleanup_command  [runs ALWAYS — success OR failure via ensure/rescue]
        → Delete credentials from agentless-source filesystem
        → Issue post-run warning if passing-mode may leave secrets in shell history:
          "Warning: credentials may remain in shell history on the source node."
```

### Provisioner Config

```yaml
provisioner:
  name: chef_infra_agentless
  version: 19.1.2        # Required; Chef Infra Client 19+ only
  data_path: test/data   # Optional: path to data bags, environments, etc.
```

### 8.1 Cross-Plugin Config Access

The provisioner (and verifier) need access to `driver.agentless:` config (credential file path, passing mode, remote node endpoints). In Test Kitchen, every plugin instance holds a reference to the parent `Kitchen::Instance` object, which in turn holds references to all other plugin instances for that instance.

```ruby
# Inside Kitchen::Provisioner::ChefInfraAgentless
def agentless_config
  instance.driver.config[:agentless]
end

def remote_node_for(instance_name)
  agentless_config[:remote_nodes][instance_name]
end

def credential_manager
  @credential_manager ||= Kitchen::Agentless::CredentialManager.new(
    credential_map_file: agentless_config[:"credential-map-file"],
    passing_mode:        agentless_config[:"credential-passing-mode"],
    source_transport:    instance.transport.connection(instance.driver.source_state)
  )
end
```

This pattern is used identically in `Kitchen::Verifier::InspecAgentless` — both share the same `CredentialManager` approach via `instance.driver`.

---

## 9. Verifier: InspecAgentless

InSpec is installed on the `agentless-source` node and executed from there targeting remote nodes — mirroring how the provisioner works. Credentials are provisioned and cleaned up on the same per-operation ephemeral lifecycle.

> **Compliance Phase (InSpec embedded in CIC):** When `chef-client --target` runs a compliance phase, it runs InSpec internally using credentials already established by the converge step. No extra credential handling is needed — it is transparent to TKE.
>
> The `inspec_agentless` verifier handles the **separate `kitchen verify` step only** (i.e., standalone InSpec runs against the target initiated by TKE).

```
Kitchen::Verifier::InspecAgentless
  │
  ├── #prepare_command  [runs during kitchen verify — before run_command]
  │     → Install Chef InSpec <version> as FULL PACKAGE on agentless-source
  │       (full package install, not gem; similar cadence to CIC install in provisioner)
  │       (skipped if already installed and version matches)
  │     → Provision credentials from kitchen-agentless-credentials.yml onto source
  │     → Issue OWASP warning if plaintext credentials
  │
  ├── #run_command
  │     → Lookup remote_node for this instance
  │     → Construct: inspec exec <profile-path>
  │                              --target <protocol>://<hostname>:<port>
  │                              [--key <ssh-key>] [--user <username>]
  │                              --reporter cli junit:<output-path>
  │     → Execute on agentless-source via source transport
  │     → Stream output back to TKE logger
  │     → Mask credential values in output
  │
  └── #cleanup_command  [runs ALWAYS — success OR failure]
        → Delete credentials from agentless-source filesystem
        → Issue warning if shell history may retain secrets
```

### Verifier Config

```yaml
verifier:
  name: inspec_agentless
  version: 5.22.0      # Optional — defaults to latest stable InSpec 5+
  # controls_dir: test/integration/default/controls  # optional, standard TK verifier config
```

---

## 10. Local Mode (source_node.mode: local)

Local mode is **not a separate driver**. It is a flag inside `driver.agentless.source_node.mode: local` that `AgentlessDriver` checks to skip source VM creation. The `sub_driver` continues to manage target nodes as normal.

```
AgentlessDriver#create — local mode path
  │
  ├── source_node[:mode] == "local"?
  │     YES →
  │       Verify chef-client is in PATH (or Workstation installed)
  │         → Raise UserError if not found with: "Local mode requires chef-client in PATH
  │            or Chef Workstation to be installed."
  │       state[:local_mode] = true
  │       Skip source VM creation entirely — NO call to sub_driver for source
  │
  ├── Target nodes are still created normally:
  │     sub_driver.create(target_state)  ← for each target instance (if volatility: ephemeral)
  │
  └── No agentless-source entry in .kitchen/ state or kitchen list

AgentlessProvisioner / AgentlessVerifier — local mode execution
  │
  └── When state[:local_mode] == true:
        Execute chef-client / inspec via Ruby system calls on workstation
        No SSH transport to a source node needed
        Temp credentials written to local /tmp/kitchen-agentless-* and cleaned up via ensure
```

---

## 11. Credential Lifecycle

### New Design: Ephemeral Per-Operation

Each operation (converge, verify) independently provisions and cleans up credentials.
Credentials **never persist** between operations on the source node.

```
kitchen converge
  ├─ ensure block wraps entire operation
  ├─ BEFORE run_command:
  │    provision credentials → agentless-source
  │    OWASP warning (if plaintext)
  ├─ DURING run_command:
  │    chef-client --target (uses credentials)
  └─ AFTER (ensure block — runs even on exception):
       delete credentials from agentless-source
       warn if shell history may retain secrets

kitchen verify
  ├─ ensure block wraps entire operation
  ├─ BEFORE run_command:
  │    provision credentials → agentless-source
  │    OWASP warning (if plaintext)
  ├─ DURING run_command:
  │    inspec exec --target (uses credentials)
  └─ AFTER (ensure block):
       delete credentials from agentless-source

kitchen destroy
  └─ Destroys VMs/containers only
     Credential cleanup is NOT needed here — already done after each operation
```

### kitchen-agentless-credentials.yml Format

This file is specific to TKE agentless mode. It is completely separate from `~/.chef/credentials`.

```yaml
# kitchen-agentless-credentials.yml

credentials:
  default-ubuntu-2204:          # key = exact instance name
    type: inline                # inline | credential-file | databag
    protocol: ssh
    username: ubuntu
    ssh_key: test/target-key.pem
    # password: plaintext       ← triggers OWASP warning

  default-windows-2025:
    type: inline
    protocol: winrm
    username: Administrator
    password: "<%= ENV['WIN_PASS'] %>"   # ERB supported

  mysuite-ubuntu-2204:
    type: credential-file       # copy file to source ~/.chef/credentials; passphrase optional
    path: test/chef-credentials
    passphrase: "<%= ENV['CRED_PASSPHRASE'] %>"
```

### Credential Types

| Type | Description | OWASP Warning? |
|---|---|---|
| `inline` | SSH/WinRM plaintext in file | **Yes** — before use + after run |
| `credential-file` | Chef credentials file copied to source; supports passphrase encryption | No (encrypted) / Yes (unencrypted) |
| `databag` | Data bag reference on source node | No |
| _(future)_ `chef360-secret` | Chef 360 Secret Service | Out of scope MVP |
| _(future)_ `vault` | HashiCorp Vault | Out of scope MVP |

### Credential Passing Modes

| Mode | Mechanism | History Risk? |
|---|---|---|
| `pass-by-env-var` | Export credentials as env vars before running chef-client/inspec | Low |
| `pass-cmd-line` | Pass credentials as CLI flags (`--password`, `--key`) | **Yes** — warn user |
| `pass-by-creds-file` | Write credentials to a temp file; pass `--credentials` flag | Low if file deleted |

### 11.1 Credential Isolation with Parallel Runs (`-c N`)

When multiple instances converge or verify concurrently, all share the same `agentless-source` node. Without isolation, one instance's `ensure` cleanup could delete another instance's credentials mid-run.

**Solution: Per-instance subdirectory on the source node.**

```
agentless-source:/tmp/
  kitchen-agentless-default-ubuntu-2204/
    credentials          ← written by instance "default-ubuntu-2204" converge
  kitchen-agentless-mysuite-ubuntu-2204/
    credentials          ← written by instance "mysuite-ubuntu-2204" converge
```

Each instance only touches its own subdirectory. Cleanup deletes only `kitchen-agentless-<instance-name>/`. Races are eliminated without any locking.

```ruby
# Kitchen::Agentless::CredentialManager
def credential_dir(instance_name)
  "/tmp/kitchen-agentless-#{instance_name}"
end
```

This pattern applies to both `pass-by-creds-file` and `pass-by-env-var` modes (env var names are also namespaced: `KITCHEN_AGENTLESS_<INSTANCE>_PASSWORD`, etc.).

---

## 12. Command Semantics

### 12.1 `kitchen create`

- Creates `agentless-source` (if not local mode) using `source_node` config + sub_driver
- Creates ALL ephemeral target instances using per-node config + sub_driver
- For `volatility: real` — creates `agentless-source` only; real targets pre-exist and are only registered in state

### 12.2 `kitchen converge`

```
kitchen converge [instance-pattern]
```

1. Install Chef Infra Client (from `provisioner.version`) on `agentless-source`
   - Native package installer only (not gem)
   - Cached: skip if already installed at correct version
2. Provision credentials to `agentless-source` (ensure block opened)
3. Run `chef-client --target <protocol>://<endpoint>` on `agentless-source`
4. Stream output to TKE logger (secrets masked)
5. **Delete credentials** (ensure block — runs even on failure)
6. Warn if shell history may retain secrets

### 12.3 `kitchen verify`

```
kitchen verify [instance-pattern]
```

1. Install Chef InSpec (from `verifier.version` or latest 5+) on `agentless-source`
   - Full package install (not gem)
   - Cached: skip if already installed at correct version
2. Provision credentials to `agentless-source` (ensure block opened)
3. Run `inspec exec <profile> --target <protocol>://<endpoint>` on `agentless-source`
4. Stream output to TKE logger (secrets masked)
5. **Delete credentials** (ensure block — runs even on failure)

### 12.4 `kitchen destroy`

```
kitchen destroy [instance-pattern]
```
Default behavior: Destroy `agentless-source` **AND** all ephemeral target instances.

```
kitchen destroy --keep-agentless-source
```
Destroy all target instances. Keep `agentless-source` running.
> "Source caching" — major optimization: avoids re-creating and re-provisioning the source on repeated `converge/verify/destroy` cycles.

```
kitchen destroy agentless-source
```
Destroy just the `agentless-source` instance.
> ⛔ **Blocked** if any target instances are still running. TKE raises:
> ```
> Error: Cannot destroy agentless-source while target instances are still running.
> Destroy all targets first with `kitchen destroy`, or preserve the source with
> `kitchen destroy --keep-agentless-source`.
> ```

**`volatility: real` targets:** `kitchen destroy` does NOT terminate real nodes. It destroys only `agentless-source` and removes TKE's tracking state for real targets.

### 12.5 `kitchen test`

`kitchen test` is the full end-to-end workflow: `create → converge → verify → destroy`. With agentless mode it works as follows:

```
kitchen test [instance-pattern] [-c N]
  │
  ├─ 1. create
  │     AgentlessDriver#create — source + targets spun up (file-locked source creation)
  │
  ├─ 2. converge
  │     Provisioner: install CIC → provision credentials → chef-client --target → cleanup creds
  │
  ├─ 3. verify
  │     Verifier: install InSpec → provision credentials → inspec exec --target → cleanup creds
  │
  └─ 4. destroy
        AgentlessDriver#destroy — all targets terminated, then source terminated
        (source only after last target, unless --keep-agentless-source)
```

**With `-c N`:** Steps 1–4 run for each instance concurrently up to N. Source creation is serialised via file lock (§6.1). Credential operations are isolated per-instance (§11.1).

**`kitchen test` does NOT pass `--keep-agentless-source` by default.** The source is destroyed at the end of the test run. Use `kitchen converge && kitchen verify` + manual `kitchen destroy --keep-agentless-source` if source caching is desired.

---

## 13. TKE Core Integration

> **Design principle:** TKE core (`chef-test-kitchen-enterprise`) must remain agentless-unaware. The agentless plugin (`kitchen-chef-infra-agentless`) hooks into TKE via generic, plugin-agnostic extension points. No agentless-specific code lives in TKE core.

### 13.1 `kitchen list` — Agentless Source Section

`kitchen list` in TKE core is extended with an optional **driver hook**: if the driver responds to `#source_info`, TKE will render an extra section above the standard instances table.

```ruby
# TKE core — lib/kitchen/command/list.rb (generic extension)
if instance.driver.respond_to?(:source_info)
  render_source_section(instance.driver.source_info)
end

# Kitchen::Driver::Agentless (in KCAI) — returns source info or nil (local mode)
def source_info
  return nil if source_node_local?
  {
    instance:      "agentless-source",
    driver:        "agentless/#{config[:sub_driver]}",
    state:         source_state[:state] || "<Not Created>",
    endpoint:      source_state[:hostname] ? "#{source_state[:hostname]}:#{source_state[:port] || 22}" : "<Not Created>",
    cic_version:   source_state[:cic_version]   || "<not installed>",
    inspec_version: source_state[:inspec_version] || "<not installed>"
  }
end
```

TKE core only knows about the `#source_info` interface — not about agentless, EC2, or Docker.

### 13.2 `--keep-agentless-source` Flag

Adding an agentless-specific CLI flag to `kitchen destroy` would couple TKE core to this plugin. Instead, a **generic driver option** is used:

```
kitchen destroy --driver-option keep_source=true
```

`AgentlessDriver#destroy` reads `options[:keep_source]` and acts accordingly. TKE core passes raw driver options through without interpreting them.

> **Alternatively**, if TKE core already supports per-driver destroy hooks (via `Driver#before_destroy` / `Driver#after_destroy`), those can be used instead. To be confirmed during Wave 5 implementation (CHEF-36826).

### 13.3 TKE Core Cleanup (Waves 1–14 Removal)

The following agentless-specific code from Waves 1–14 is **deleted from TKE core** in Wave 1 (CHEF-27348):

| File | What is removed |
|---|---|
| `lib/kitchen/agentless/context.rb` | `Kitchen::Agentless::Context` class |
| `lib/kitchen/agentless/remote_node.rb` | Old `RemoteNode` (moved to KCAI) |
| `lib/kitchen/agentless/credential_resolver.rb` | `CredentialResolver` (replaced by `CredentialManager` in KCAI) |
| `lib/kitchen/agentless/warnings.rb` | `Warnings` module (moved into `CredentialManager`) |
| `lib/kitchen/provisioner/base.rb` | `#agentless_mode?` method + `default_config :agentless` |

After this cleanup, **TKE core has zero agentless-specific code**. The only additions are the two generic hooks in §13.1 and §13.2.

---

## 14. Target Assignment Model

Assignment is **explicit only** (no pool / round-robin — removed). The `remote_nodes:` hash keys must exactly match the `<suite>-<platform>` instance names TKE generates.

```yaml
driver:
  agentless:
    remote_nodes:
      default-ubuntu-2204:    # ← must match exactly
        transport:
          hostname: 10.0.0.5
      mysuite-ubuntu-2204:    # ← must match exactly
        transport:
          hostname: 10.0.0.6
```

**Validation errors raised at config load time:**
- Instance name not in `remote_nodes` → `UserError: no target assigned for instance 'X'`
- `remote_nodes` is an Array (old pool format) → `UserError` with migration instructions
- `driver:` key inside a `remote_nodes` entry under `volatility: real` → `UserError`

---

## 15. Volatility: Ephemeral vs Real

| | Ephemeral | Real |
|---|---|---|
| **`kitchen create`** | Creates source + all targets | Creates source only; targets pre-exist |
| **`kitchen destroy`** | Destroys source + all targets | Destroys source only; clears target state |
| **`driver:` in remote_nodes** | ✅ Allowed (per-target override) | ❌ Not permitted — raises `UserError` |
| **`transport.hostname` required** | No (driver provides it) | **Yes** — TKE cannot discover it |
| **Use case** | CI, dev — fresh VMs each run | Edge devices, on-prem, fixed-IP hosts |

---

## 16. Docker SSH Images

### Why Custom Images Are Needed

Standard Docker images (`ubuntu:22.04`, `windows/servercore:2025`) do not include an SSH daemon. `kitchen-docker` (unlike Dokken) requires SSH to connect into containers. Therefore, Chef must publish and maintain SSH-enabled base images for use as agentless targets.

### Image Strategy

Chef publishes two categories of images:

| Image | Purpose | Contains |
|---|---|---|
| `chef/agentless-source:<cic-version>` | Source node | Base OS + Chef Infra Client + SSH server |
| `chef/agentless-target-<platform>` | Target nodes | Base OS + SSH server (no chef-client) |

**Initial MVP target images (Linux only):**
- `chef/agentless-source:19` — Ubuntu 22.04 base + Chef Infra Client 19 + OpenSSH
- `chef/agentless-target-ubuntu-2204` — Ubuntu 22.04 + OpenSSH (no chef-client)
- `chef/agentless-target-ubuntu-2404` — Ubuntu 24.04 + OpenSSH (no chef-client)

> ⚠️ **Windows Docker containers are deferred from MVP.**
> Windows containers require Hyper-V isolation and have a fundamentally different runtime from Linux. The complexity is significant and out of proportion for an MVP. Windows target support via Docker is a post-MVP story. WinRM transport against real (non-Docker) Windows targets (CHEF-34939) remains in scope as it does not require Docker images.

**Future images (post-MVP):**
- `chef/agentless-target-windows-2025` — Windows Server 2025 + WinRM

### Future Enhancement: Auto-Rebuild
The Jira notes that TKE may be able to auto-add SSH to a user-specified base image locally (e.g., `docker build` with an SSH layer on top). This is a future enhancement — not MVP scope. A dedicated story exists for this (see §18.4 NEW-012).

---

## 17. Sequence Diagrams

### `kitchen create` — EC2 Ephemeral

```
User       TK Core      AgentlessDriver    EC2SubDriver
  │              │               │               │
  │ create       │               │               │
  │─────────────►│               │               │
  │              │ driver.create (target instance)│
  │              │──────────────►│               │
  │              │               │ sub_driver.create(target_state)
  │              │               │──────────────►│ Launch target EC2
  │              │               │◄──────────────│ state[:hostname, :server_id]
  │              │               │               │
  │              │               │ [if source not yet running]
  │              │               │ source_sub_driver.create(source_state)
  │              │               │──────────────►│ Launch source EC2
  │              │               │◄──────────────│ source_state[:hostname]
  │              │◄──────────────│               │
  │◄─────────────│               │               │
```

### `kitchen converge` — EC2 Ephemeral

```
User    TK Core  AgentlessProvisioner  SourceTransport(SSH)  agentless-source  TargetNode
  │          │              │                   │                  │               │
  │ converge │              │                   │                  │               │
  │─────────►│              │                   │                  │               │
  │          │ call(state)  │                   │                  │               │
  │          │─────────────►│                   │                  │               │
  │          │              │ [ensure block start]                 │               │
  │          │              │ 1. install CIC 19.x on source        │               │
  │          │              │────────────────────────────────────► │ apt/yum/...   │
  │          │              │ 2. provision credentials             │               │
  │          │              │────────────────────────────────────► │ write creds   │
  │          │              │    [OWASP warn if plaintext]         │               │
  │          │              │ 3. run chef-client --target          │               │
  │          │              │────────────────────────────────────► │               │
  │          │              │                   │                  │ chef-client   │
  │          │              │                   │                  │ --target ────►│ SSH/WinRM
  │          │              │◄──────────────────│──────────────────│ stream output │
  │          │              │ 4. [ensure] delete credentials       │               │
  │          │              │────────────────────────────────────► │ rm creds      │
  │          │◄─────────────│                   │                  │               │
  │◄─────────│              │                   │                  │               │
```

### `kitchen destroy --keep-agentless-source`

```
User      TK Core      AgentlessDriver   EC2SubDriver
  │             │               │              │
  │ destroy     │               │              │
  │ --keep-src  │               │              │
  │────────────►│               │              │
  │             │ driver.destroy (targets only) │
  │             │──────────────►│              │
  │             │               │ sub_driver.destroy(target_state) × N
  │             │               │─────────────►│ Terminate EC2 target
  │             │               │◄─────────────│
  │             │               │ SKIP source destroy (--keep flag set)
  │             │◄──────────────│              │
  │◄────────────│               │              │
```

---

## 18. Component Reference

### Classes in `kitchen-chef-infra-agentless`

| File | Class | Role |
|---|---|---|
| `lib/kitchen/driver/agentless.rb` | `Kitchen::Driver::Agentless` | Superdriver; reads `driver.agentless:` config; orchestrates source + target lifecycle; handles `source_node.mode: local` internally |
| `lib/kitchen/driver/agentless_source.rb` | `Kitchen::Driver::AgentlessSource` | Thin sub-driver adapter for source node; applies `source_node` config overrides |
| `lib/kitchen/provisioner/chef_infra_agentless.rb` | `Kitchen::Provisioner::ChefInfraAgentless` | Installs CIC 19+; provisions creds; runs `--target`; cleanup |
| `lib/kitchen/verifier/inspec_agentless.rb` | `Kitchen::Verifier::InspecAgentless` | Installs InSpec 5+; provisions creds; runs `inspec exec --target`; cleanup |
| `lib/kitchen/agentless/config.rb` | `Kitchen::Agentless::Config` | Parses + validates `driver.agentless:` block |
| `lib/kitchen/agentless/remote_node.rb` | `Kitchen::Agentless::RemoteNode` | Value object: one target node's config (transport, driver overrides, creds) |
| `lib/kitchen/agentless/credential_manager.rb` | `Kitchen::Agentless::CredentialManager` | Provision / delete credentials on source; OWASP warnings; secret masking |

### Changes in `chef-test-kitchen-enterprise` (TKE Core)

| File | Change |
|---|---|
| `lib/kitchen/command/list.rb` | Add separate `Agentless Source` section above target instances table |
| `lib/kitchen/instance.rb` | Recognize `agentless-source` as reserved instance name (no suite/platform decomposition); raise `UserError` at config load if a suite+platform combo would generate the name `agentless-source` |

### Code to Remove From Previous Implementation

All of the following are **deleted** — they are replaced by the components above:

| Location | Class/Method | Reason |
|---|---|---|
| TKE core `lib/kitchen/agentless/context.rb` | `Kitchen::Agentless::Context` | Replaced by `Kitchen::Agentless::Config` in KCAI |
| TKE core `lib/kitchen/agentless/remote_node.rb` | `Kitchen::Agentless::RemoteNode` | Moved to KCAI |
| TKE core `lib/kitchen/agentless/credential_resolver.rb` | `Kitchen::Agentless::CredentialResolver` | Replaced by `CredentialManager` in KCAI |
| TKE core `lib/kitchen/agentless/warnings.rb` | `Kitchen::Agentless::Warnings` | Moved to KCAI `CredentialManager` |
| TKE core `lib/kitchen/provisioner/base.rb` | `#agentless_mode?`, `default_config :agentless` | Agentless is now a driver concern |
| KCAI old provisioner | `ChefInfraAgentless` (Waves 1–14 version) | Full rewrite |
| KCAI old lib | Pool/Explicit assignment classes | Removed — explicit only |
| KCAI old lib | `ParallelRunner` | Removed — use `kitchen -c N` |

---

## 19. Story Review: Old vs New

### 18.1 Stories Still Valid (scope changes)

| Story | Summary | What Changes |
|---|---|---|
| CHEF-27355 | Passphrase on credentials file | Still valid. `credential-file` type with passphrase. Moves to `CredentialManager` in KCAI. |
| CHEF-27346 | Mask secrets + warn insecure | Still valid. OWASP warnings now at converge AND verify. |
| CHEF-27347 | Error handling for incompatible resources | Still valid. Chef 19+ is now a hard validation, not advisory. |
| CHEF-27345 | Documentation | Still valid; **full rewrite** needed for new architecture. |
| CHEF-34939 | Qmetry test cases | Still valid. |
| CHEF-34937 | ERB dynamic target lists | Still valid. Already in TKE; needs testing + docs for agentless context. |
| CHEF-34938 | WinRM / Windows targets | Still valid. WinRM transport for Windows. |

### 18.2 Stories That Need Significant Rework

| Story | Summary | What Needs Rework |
|---|---|---|
| CHEF-27349 | Agentless Provisioner + schema | Full rewrite. Provisioner and new superdriver both need building. `agentless:` block moves inside `driver:`. All TKE core agentless code removed. |
| CHEF-27348 | Backward compatibility | Still needed. Non-agentless kitchens unaffected. Validation logic changes (driver-level, not provisioner-level). |
| CHEF-34610 | Target node assignment | Pool removed. Explicit hash only. Simpler. But must handle new error cases (missing assignment, Array format migration). |
| CHEF-27350 | Provision source container + kitchen create | Source lifecycle moves from provisioner `after_create` hook into the `AgentlessDriver#create`. |
| CHEF-27351 | Agentless call — real mode | Still needed. Now called `volatility: real`. Lives in provisioner `#run_command`. |
| CHEF-27352 | Agentless call — container mode | Still needed. Docker (not Dokken) + SSH-enabled images. Requires Docker image story (NEW-004). |
| CHEF-27353 | Collect results + forward to TKE | Still needed. Output streaming from source to TKE logger. |
| CHEF-27354 | Secret cleanup + kitchen destroy | **Major rework.** Cleanup is now per-operation (converge + verify), not on destroy. `ensure` block pattern. |

### 18.3 Stories No Longer Needed

| Story | Reason |
|---|---|
| CHEF-34459 | `parallel-mode` config removed. Parallel execution is native TK: `kitchen converge -c N`. Close/descope. |

### 18.4 New Stories Required

| Proposed Key | Summary | Priority | Notes |
|---|---|---|---|
| NEW-001 | Superdriver scaffolding: `Kitchen::Driver::Agentless` + `AgentlessSource` + `Kitchen::Agentless::Config` + `RemoteNode` + local mode (`source_node.mode: local`) | P0 — blocks everything | Foundation of all agentless work |
| NEW-002 | KCAI repo cleanup: remove all Waves 1–14 code; set up new folder structure; update gemspec | P0 — run with NEW-001 | Clean slate before building |
| NEW-003 | EC2 source + target lifecycle via superdriver (ephemeral + real) | P1 — MVP | Proves generality #1 |
| NEW-004 | Docker source + target lifecycle via superdriver + SSH-enabled images | P1 — MVP | Proves generality #2 |
| NEW-005 | `kitchen list` separate `Agentless Source` section (TKE core change) — columns: Instance, Driver, State, Endpoint, CIC Version, InSpec Version | P2 — UX | Was NEW-010 |
| NEW-006 | `Kitchen::Verifier::InspecAgentless` — InSpec on source, credentials, cleanup | P1 — InSpec now in scope | Was NEW-006 |
| NEW-007 | `CredentialManager`: per-operation ephemeral credential lifecycle (ensure blocks) | P1 — security requirement | Shared by provisioner + verifier |
| NEW-008 | `kitchen destroy --keep-agentless-source` flag | P2 — source caching | Key optimization per AC |
| NEW-009 | Block `kitchen destroy agentless-source` when targets running; hard error, no `--force` | P2 — safety | |
| NEW-011 | Build + publish Chef SSH-enabled Docker images (`chef/agentless-source`, `chef/agentless-target-*`) | P1 — needed before Docker testing | **Planned separately** — not tracked in this epic |
| NEW-012 | Auto-rebuild user-supplied Docker images with SSH layer | P3 — future enhancement | Not MVP |

---

## 20. Decision Log

All architecture questions have been resolved. This section records all decisions, including those added during implementation review (v3).

### v1/v2 Decisions (product team Q&A, 2026-07-06/07)

| # | Question | Decision |
|---|---|---|
| 1 | Where does `agentless:` live in kitchen.yml? | **Inside `driver:`** — driver owns all node lifecycle. |
| 2 | Single repo or three separate gems? | **`kitchen-chef-infra-agentless` (existing repo)** — driver, provisioner, and verifier all in one gem. Split into separate gems is a post-MVP decision. |
| 3 | Docker image rebuild responsibility? | **Chef publishes SSH-enabled images** (`chef/agentless-source`, `chef/agentless-target-*`). Auto-rebuild of user images is a future enhancement (NEW-012). |
| 4 | `agentless-source` in `kitchen list` — placement? | **Separate section** above the target instances table, with columns: Instance, Driver, State, Endpoint, CIC Version, InSpec Version. |
| 5 | Gem name vs class/plugin names? | **Gem keeps name `kitchen-chef-infra-agentless`.** Class names (and therefore `name:` values in kitchen.yml) are independent and named as makes sense: `agentless`, `chef_infra_agentless`, `inspec_agentless`. |
| 6 | InSpec credential passing in verifier? | **Yes** — `InspecAgentless` verifier provisions credentials to the source node before running `inspec exec --target`, then deletes them. Same ephemeral lifecycle as the provisioner. |
| 7 | Verifier in its own gem or same repo? | **Same repo for now** (`kitchen-chef-infra-agentless`). Moving to `kitchen-inspec-agentless` is a post-MVP decision. |
| 8 | Block `kitchen destroy agentless-source` when targets running? | **Yes, hard block.** No `--force` override. Error message directs user to run `kitchen destroy` or `kitchen destroy --keep-agentless-source`. |
| 9 | Local mode — separate driver gem or internal? | **Internal to `AgentlessDriver`.** Local mode is declared via `source_node.mode: local` inside `driver.agentless:`. No `sub_driver: local` or separate `Kitchen::Driver::Local` class. The `sub_driver` still creates ephemeral target nodes when `volatility: ephemeral`. |
| 10 | `kitchen list` source section columns? | **Confirmed:** Instance \| Driver \| State \| Endpoint \| CIC Version \| InSpec Version. Uninstalled versions show `<not installed>`. |
| 11 | Docker image pipeline ownership? | **Planned separately** — not part of this epic's stories. Tracked as a dependency (NEW-011). |
| 12 | `agentless-source` name collision detection? | **Yes** — TKE raises `UserError` at config load time if any suite+platform combo generates the reserved name `agentless-source`. |

### v3 Decisions (implementation review, 2026-07-10)

| # | Question | Decision |
|---|---|---|
| 13 | How to prevent race condition when `kitchen create -c N` runs multiple target creates concurrently? | **File lock on source creation.** `AgentlessDriver#create` acquires an exclusive lock on `.kitchen/agentless-source.lock` before checking and creating the source. Double-check after lock acquisition. Target creation (per-instance) remains fully parallel. |
| 14 | How to prevent credential conflicts when `kitchen converge -c N` runs concurrently on same source? | **Per-instance subdirectory on source node.** Each instance writes to `/tmp/kitchen-agentless-<instance-name>/`. Cleanup only touches that instance's directory. No locking needed. |
| 15 | How does `kitchen list` show the Agentless Source section without coupling TKE core to agentless? | **Generic driver hook `#source_info`.** TKE core calls `driver.source_info` if the method exists and renders the extra section. Agentless-unaware for all other drivers. |
| 16 | How does `--keep-agentless-source` work without adding agentless-specific flags to TKE core? | **Generic `--driver-option` passthrough.** TKE core's destroy command passes raw driver options; `AgentlessDriver` reads `options[:keep_source]`. No agentless-specific TKE core code. To be confirmed against TKE core extensibility in Wave 5. |
| 17 | How do provisioner and verifier access `driver.agentless:` config (cross-plugin access)? | **Via `instance.driver`.** TK instance objects hold refs to all sibling plugins. `instance.driver.config[:agentless]` is the access path inside provisioner/verifier. |
| 18 | Is `kitchen test` supported? Any special source lifecycle handling needed? | **Yes, works as-is.** `kitchen test` runs create → converge → verify → destroy sequentially per instance. Source is created once (lock), used for all operations, destroyed last. No special handling needed beyond what individual phases already implement. |
| 19 | Is local mode + Docker sub-driver supported? | **Yes — this is the primary dev workflow.** Workstation as source + Docker containers as targets. Added as §4.5 with full kitchen.yml example. |
| 20 | Are Windows Docker containers in MVP scope? | **No — deferred.** Windows containers require Hyper-V isolation and add disproportionate complexity. Linux Docker targets only for MVP. WinRM against real Windows targets (CHEF-34939) remains in scope. |

---

*Document v3 — 2026-07-10*
*Updated with implementation review findings: concurrency safety, credential isolation, TKE core decoupling, cross-plugin config access, kitchen test flow, local+Docker example, Windows Docker deferral.*
