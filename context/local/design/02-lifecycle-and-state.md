# Lifecycle & State

## The five actions

Every Instance moves through an ordered vector of transitions defined in
`Kitchen::Instance::FSM`:

```ruby
TRANSITIONS = %i{destroy create converge setup verify}.freeze
```

| Action     | Owner        | Meaning                                                        |
| ---------- | ------------ | -------------------------------------------------------------- |
| `destroy`  | Driver       | Tear down the compute target; clears persisted state           |
| `create`   | Driver       | Provision the compute target (VM/container/cloud/bare metal)   |
| `converge` | Provisioner  | Install the config tool and apply configuration (Chef/shell)   |
| `setup`    | (legacy)     | Legacy prep step; mostly a no-op for modern transports         |
| `verify`   | Verifier     | Run tests (InSpec/Busser) asserting desired state              |

## How transitions are computed

`FSM.actions(last, desired)` returns the list of actions needed to move from the
last recorded state to the desired one:

- Indexes both states in the `TRANSITIONS` vector.
- If moving **forward**, it returns the slice *between* `last+1` and `desired`
  (inclusive). E.g. from `create` to `verify` → `[converge, setup, verify]`.
- If already at or **past** the desired state, it returns just `[desired]` — so
  re-running `converge` on an already-converged box just converges again;
  asking to `destroy` always just destroys.

`Instance#transition_to(desired)` iterates those actions and, for each, wraps it
in the lifecycle hooks runner before invoking `#<action>_action`.

```
kitchen verify  (fresh instance, no state)
   └─ FSM.actions(nil, :verify) => [create, converge, setup, verify]
        create_action  → driver.create(state)
        converge_action→ provisioner.check_license; provisioner.call(state)
        setup_action   → (legacy no-op for modern drivers)
        verify_action  → verifier.call(state)
```

`kitchen test` is a higher-level convenience (`Instance#test`): it
`destroy`s first for a clean slate, then `verify`s (running the full arc), then
`destroy`s again depending on `destroy_mode`:

- `:passing` (default) — destroy only if verify succeeded.
- `:always` — always destroy (in an `ensure`).
- `:never` — leave the instance up for debugging.

## State persistence (`lib/kitchen/state_file.rb`)

State is stored per-instance as YAML at:

```
<kitchen_root>/.kitchen/<instance-name>.yml
```

The state hash carries whatever the driver/transport need to reconnect
(hostname, port, ssh key, server id, …) plus bookkeeping keys:

- `:last_action` — the last successfully completed action (drives the FSM).
- `:last_error`  — class name of the last error, or `nil` on success.

`StateFile` supports `read`, `write`, `destroy`, and `diagnose`. `destroy`
removes the file, which is why a `destroy` action effectively resets the
instance to the "nothing done yet" state.

## The action wrapper (`Instance#action`)

Every concrete action funnels through `#action(what) { |state| ... }`, which is
the reliability backbone:

1. Reads current state.
2. Runs the block under `synchronize_or_call` (mutex if the plugin declared
   `no_parallel_for`, otherwise directly) while timing it with `Benchmark`.
3. On success: sets `state[:last_action] = what`, clears `last_error`.
4. On `ActionFailed`: logs, records `last_error`, and re-raises as
   `InstanceFailure` with a pointer to `.kitchen/logs/<name>.log`.
5. On any other exception: logs, records `last_error`, re-raises as
   `ActionFailed` (indicating a probable bug/race/transient IO error).
6. **`ensure`**: always writes the state file.

The `ensure`-write guarantees that even a partial/failed run leaves an accurate
`last_action`/`last_error` on disk, so a subsequent invocation resumes correctly
and reports the prior failure.

## Concurrency & serialization

`synchronize_or_call(what, state)` decides whether an action must be serialized:

- If the plugin class registered the action via `no_parallel_for`, the action
  runs inside that plugin class's shared `Mutex` (from the Instance-level mutex
  table). This is how, e.g., a driver that hits a rate-limited API or a
  non-reentrant local hypervisor avoids concurrent create/destroy collisions.
- Otherwise the block runs directly, allowing full parallelism across instances.

`Dir.chdir` is separately guarded by `Kitchen.mutex_chdir` because it mutates
process-global CWD.

## Auxiliary (non-FSM) actions

Beyond the five lifecycle transitions, an Instance exposes operator actions that
read the existing state rather than advancing it:

- `login` — `exec`s the transport's login command (SSH/WinRM console). Never
  returns (replaces the process). Requires the instance to have been created.
- `remote_exec(cmd)` — opens a transport connection and runs an arbitrary
  command.
- `package_action` — delegates to `driver.package(state)` to produce an image.
- `doctor_action` — asks each plugin to self-diagnose common misconfigurations.
- `diagnose` / `diagnose_plugins` — dump merged config and plugin metadata for
  troubleshooting (`kitchen diagnose`).
