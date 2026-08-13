# Architecture

## Layered view

Test Kitchen is organized as a set of cooperating layers. Data flows downward
from user configuration into concrete runtime objects; control flows through the
CLI into per-instance action orchestration.

```
┌──────────────────────────────────────────────────────────────┐
│  CLI layer            bin/kitchen → Kitchen::CLI (Thor)        │
│                       parses ARGV, dispatches to Command class │
├──────────────────────────────────────────────────────────────┤
│  Command layer        Kitchen::Command::*                      │
│                       (test, list, login, exec, package, ...)  │
│                       selects instances, calls actions on them │
├──────────────────────────────────────────────────────────────┤
│  Config/Factory layer Kitchen::Config                          │
│                       Loader(YAML+ERB) → DataMunger(merge)     │
│                       → builds immutable Instance objects      │
├──────────────────────────────────────────────────────────────┤
│  Instance layer       Kitchen::Instance + FSM                  │
│                       orchestrates create→converge→setup→      │
│                       verify→destroy, persists state           │
├──────────────────────────────────────────────────────────────┤
│  Plugin layer         Driver | Provisioner | Transport |       │
│                       Verifier | LifecycleHooks                │
│                       (dynamically loaded gems)                │
├──────────────────────────────────────────────────────────────┤
│  Cross-cutting        Configurable (config DSL), Logging,      │
│                       ShellOut, Errors, Licensing (enterprise) │
└──────────────────────────────────────────────────────────────┘
```

## Module entry point (`lib/kitchen.rb`)

`lib/kitchen.rb` is the wiring hub. It:

1. `require_relative`s every core module and the plugin base classes.
2. Defines the `Kitchen` module singleton state:
   - `Kitchen.logger` — the shared logger.
   - `Kitchen.mutex` — global coordination mutex.
   - `Kitchen.mutex_chdir` — a dedicated mutex to serialize `Dir.chdir` (needed
     because chdir is process-global but instances run in parallel threads).
3. Provides logger factories (`default_logger`, `default_file_logger`) that
   respect `KITCHEN_LOG` / `KITCHEN_LOG_OVERWRITE` env vars.
4. Declares defaults: `DEFAULT_TEST_DIR = "test/integration"`,
   `DEFAULT_LOG_DIR = ".kitchen/logs"`, `DEFAULT_LOG_LEVEL = :info`.

## The Config factory (`lib/kitchen/config.rb`)

`Kitchen::Config` is the **factory that turns parsed data into runtime objects**.
Its design contract is important:

- Most produced objects are treated as **immutable** and are **memoized**. Once
  you call `#instances`, you always get back the same `Instance` objects.
- All thread-unsafe data manipulation happens here, up front, so that the
  resulting Instances can be safely executed in concurrent threads.

Responsibilities:
- Holds `kitchen_root`, `log_root`, `test_base_path`, `log_level`, etc.
- Owns the `loader` (reads `kitchen.yml`).
- Builds `Collection<Instance>` by expanding suites × platforms, constructing a
  Driver, Provisioner, Transport, Verifier, LifecycleHooks and StateFile for
  each, and injecting them into `Instance.new`.

## Runtime object graph (per instance)

```
Instance
 ├─ suite        : Suite        (name + test config)
 ├─ platform     : Platform     (name, os_type, transport hints)
 ├─ driver       : Driver::Base subclass       ── manages compute
 ├─ provisioner  : Provisioner::Base subclass   ── converges config
 ├─ transport    : Transport::Base subclass      ── remote exec/file xfer
 │    └─ connection(state) : Transport::Base::Connection
 ├─ verifier     : Verifier::Base subclass        ── runs tests
 ├─ lifecycle_hooks : LifecycleHooks              ── pre/post shims
 └─ state_file   : StateFile                      ── persisted state
```

At construction (`Instance#initialize`), each plugin gets `finalize_config!(self)`
called, which back-references the instance into the plugin and locks in
configuration. Each plugin class is also registered into a per-class **mutex
table** if it declared `no_parallel_for` (see concurrency below).

## Concurrency model

- Instances run in parallel across threads (the CLI caps concurrency).
- Plugins that are **not** thread-safe for particular actions declare
  `no_parallel_for :create, :destroy` (via `Kitchen::Plugin::Base`). The
  Instance layer creates a shared `Mutex` per plugin **class** and serializes
  those actions across all instances using that plugin.
- `Kitchen.mutex_chdir` specifically guards `Dir.chdir`, which is global to the
  process and would otherwise corrupt parallel instances.
- Because `Config` pre-computes everything immutably, the hot parallel path
  avoids shared mutable state except through these explicit mutexes.

## Error taxonomy (`lib/kitchen/errors.rb`)

Errors are split by *who is at fault*, which drives how they're reported:

- **`UserError`** — the user's config or environment is wrong (bad option,
  missing license, unreachable host). Reported cleanly, no stack spew.
- **`ClientError`** — a plugin/programming contract was violated (missing
  required constructor option, plugin failed to load).
- **`ActionFailed`** — an action (create/converge/…) failed at runtime.
- **`InstanceFailure` / `TransientFailure`** — wrap failures for aggregate
  reporting across many instances.

This separation lets the CLI show friendly messages for user mistakes while
still surfacing real bugs.

## Enterprise delta

Compared with upstream Test Kitchen, the enterprise fork inserts a
**licensing cross-cutting concern**:

- `lib/kitchen/licensing/config.rb` configures `chef-licensing` at load time
  (product name, entitlement id, license server).
- `lib/kitchen/plugin.rb` re-asserts the licensing config after loading each
  plugin (a plugin gem may have its own `chef-licensing` config that would
  otherwise clobber Kitchen's).
- The `converge` action calls `provisioner.check_license` before doing work.

See `06-enterprise-licensing.md` for detail.
