# Chef Test Kitchen Enterprise — Design Overview

> Version analyzed: **2.0.19** (`lib/kitchen/version.rb`)
> Ruby: 3.1+ (dev environment uses 3.4.8)

## What it is

Test Kitchen is an **integration-testing harness** for infrastructure code
(primarily Chef cookbooks, but also shell scripts and any other converge-able
automation). It creates isolated target platforms (VMs, containers, cloud
instances, bare metal), applies configuration to them, runs verification tests,
and tears them down.

`chef-test-kitchen-enterprise` is the enterprise fork of the open-source
`test-kitchen` project, maintained by Progress/Chef. The main enterprise
addition on top of upstream Test Kitchen is **Chef Licensing integration**
(license activation and enforcement via `chef-licensing`). A backward-compatible
`test-kitchen` alias gem redirects to this implementation.

> **Fork caveat:** this is not simply "latest upstream + licensing." Beyond the
> licensing additions, the two codebases have diverged in both directions — this
> fork retains legacy SSH (`driver/ssh_base`) that upstream dropped and lacks
> some upstream additions (`kitchen logs`, the `external` provisioner). Note that
> Chef Test Kitchen Enterprise uses its **own independent version numbering**, so
> its version (`2.0.19`) is not comparable to upstream's (`4.1.1`) and implies
> nothing about lineage or recency. See `06-enterprise-licensing.md` → "Upstream
> relationship & concrete divergences".

## Core mental model

A **run** is defined by the cross-product of **suites** × **platforms**. Each
pair is an **Instance**. Every Instance is driven through an ordered lifecycle
by five pluggable subsystems:

```
        ┌─────────────────────────────────────────────────────────┐
        │                        Instance                          │
        │   (one suite × one platform, e.g. default-ubuntu-22.04)  │
        └─────────────────────────────────────────────────────────┘
              │          │           │           │           │
         ┌────▼───┐ ┌────▼─────┐ ┌───▼─────┐ ┌───▼────┐ ┌────▼─────┐
         │ Driver │ │Provision-│ │Transport│ │Verifier│ │Lifecycle │
         │        │ │   er     │ │         │ │        │ │  Hooks   │
         └────────┘ └──────────┘ └─────────┘ └────────┘ └──────────┘
          create/    converge     ssh/winrm   inspec/     pre/post
          destroy    (chef/shell) /exec       busser      action shims
```

| Subsystem     | Responsibility                                             | Base class                         |
| ------------- | ---------------------------------------------------------- | ---------------------------------- |
| **Driver**    | Provision & destroy the compute target                     | `Kitchen::Driver::Base`            |
| **Provisioner** | Install & run the configuration tool (Chef, shell)       | `Kitchen::Provisioner::Base`       |
| **Transport** | Move files & run remote commands (SSH, WinRM, exec)        | `Kitchen::Transport::Base`         |
| **Verifier**  | Run the tests that assert desired state (InSpec, Busser)   | `Kitchen::Verifier::Base`          |
| **Lifecycle Hooks** | Run arbitrary local/remote commands around actions   | `Kitchen::LifecycleHooks`          |

All four primary plugin types plus lifecycle hooks are **swappable** and
discovered dynamically off the Ruby `$LOAD_PATH` by naming convention, so they
ship as independent gems (`kitchen-ec2`, `kitchen-vagrant`, `kitchen-dokken`,
`kitchen-inspec`, etc.).

## The lifecycle state machine

Actions are strictly ordered. A tiny finite-state machine
(`Kitchen::Instance::FSM`) computes which transitions to run to move an instance
from its last recorded state to the desired state:

```
destroy → create → converge → setup → verify
```

- Asking for `converge` when the instance is only `create`d runs just
  `converge`. Asking for `verify` from scratch runs
  `create → converge → setup → verify` in sequence.
- `kitchen test` runs the full arc and (by default) destroys on success.
- State is persisted per-instance in `.kitchen/<instance>.yml` (see the State &
  Config doc).

## Documents in this set

| File | Topic |
| ---- | ----- |
| `00-overview.md` | This file — the big picture |
| `01-architecture.md` | Layered architecture, module map, runtime object graph |
| `02-lifecycle-and-state.md` | The action FSM, state file, transitions, concurrency |
| `03-plugin-system.md` | How drivers/provisioners/transports/verifiers are built & loaded |
| `04-configuration.md` | `kitchen.yml`, DataMunger merge semantics, Configurable DSL |
| `05-cli-and-commands.md` | Thor CLI, command classes, action dispatch |
| `06-enterprise-licensing.md` | Chef Licensing integration (the enterprise delta) |
| `07-testing-and-build.md` | Test suites, Cucumber features, Rake/Expeditor build |

## Key source-tree map

```
lib/kitchen.rb              # Module entry point; wires requires, global logger/mutexes
lib/kitchen/
  cli.rb                    # Thor CLI definition (subcommands)
  command/                  # One class per CLI subcommand (test, list, login, ...)
  config.rb                 # Factory: turns parsed data into Instance objects
  data_munger.rb            # Recursive merge of common/platform/suite config
  loader/yaml.rb            # Reads & ERB-renders kitchen.yml
  instance.rb               # The Instance + FSM + action orchestration
  configurable.rb           # default_config / required_config DSL, validation
  plugin.rb / plugin_base.rb# Dynamic plugin loading + no_parallel_for
  driver/ provisioner/ transport/ verifier/   # Built-in plugin bases + reference impls
  lifecycle_hooks.rb        # pre/post action hook runner
  licensing/                # ENTERPRISE: chef-licensing configuration & enforcement
  state_file.rb             # Per-instance persisted state
  errors.rb                 # Exception taxonomy (UserError, ClientError, ...)
```
