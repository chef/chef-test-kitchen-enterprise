# Configuration

## The `kitchen.yml` file

A project's testing matrix is declared in `kitchen.yml` at the project root. It
has five top-level sections; four configure the plugin subsystems and two
(`platforms`, `suites`) define the matrix that gets multiplied into instances.

```yaml
driver:                       # which compute backend (+ its options)
  name: vagrant
  linked_clone: false

provisioner:                  # how to converge config (Chef, shell, ...)
  name: chef_infra
  product_name: chef
  chef_license: accept-no-persist

verifier:                     # how to test (InSpec, Busser, shell)
  name: inspec

platforms:                    # the OS targets (rows of the matrix)
  - name: almalinux-9
  - name: ubuntu-24.04
  - name: windows-2025
    driver:                   # per-platform override
      box: stromweld/windows-2025
      customize: { memory: 4096 }

suites:                       # the test bundles (columns of the matrix)
  - name: default
    verifier:
      inspec_tests:
        - test/integration/default
```

`platforms × suites` = instances. The example above yields
`default-almalinux-9`, `default-ubuntu-24.04`, `default-windows-2025`.

## Loading (`lib/kitchen/loader/yaml.rb`)

The YAML loader reads and merges up to three files, each optionally
ERB-processed:

| Source | Default path | Purpose |
| ------ | ------------ | ------- |
| **Global** | `~/.kitchen/config.yml` | User-wide defaults across all projects |
| **Project** | `./kitchen.yml` (or `$KITCHEN_YAML`) | The main, version-controlled config |
| **Local** | `./kitchen.local.yml` | Machine-specific, usually git-ignored overrides |

Behavior:
- **ERB** is processed by default (`process_erb: true`), so `kitchen.yml` can
  embed Ruby — e.g. `<%= ENV['BOX_URL'] %>` or loops generating platforms.
- Local and global merging can be toggled (`process_local`, `process_global`).
- The three sources are deep-merged (global < project < local precedence) into a
  single raw data hash handed to the `DataMunger`.

## Merge semantics (`lib/kitchen/data_munger.rb`)

`DataMunger` performs the **recursive merge** that turns the layered raw data
into a fully-resolved config hash per (suite, platform, plugin-type). This is
the trickiest part of the system (the source even jokes about your "fear factor
level").

Precedence, from lowest to highest:

```
common block  <  platform block  <  suite block  <  suite+platform overrides
```

So a `driver:` set at the top level applies everywhere, but a `driver:` nested
under a specific platform (as in the `windows-2025` example) overrides it just
for instances on that platform. Suite-level settings override platform-level;
the most specific suite×platform combination wins.

DataMunger **mutates** the incoming hash and is explicitly documented as
**not** thread-safe / not reusable — which is why all of this happens up front
inside the single-threaded `Config` factory, before any parallel instance
execution begins.

## From data to objects (`lib/kitchen/config.rb`)

`Kitchen::Config` consumes the munged data and, for each suite×platform pair,
constructs the concrete plugin objects (via `Plugin.load`) and assembles an
`Instance`. Because everything is resolved and memoized here, the resulting
`Instance` objects are effectively immutable and safe to run in parallel
threads.

## Per-plugin configuration surface

Each plugin declares its own accepted options through the **Configurable DSL**
(see `03-plugin-system.md`): `default_config`, `required_config`,
`expand_path_for`, `deprecate_config_for`. The merged `kitchen.yml` values for
that plugin block are layered on top of the plugin's declared defaults, then
validated. Unknown/missing required keys raise `UserError` at
`finalize_config!` time, before any action runs.

## Inspecting resolved config

`kitchen diagnose` dumps the fully-merged, post-DataMunger configuration for
every instance plus plugin metadata (class, versions, API version). This is the
authoritative way to answer "what value did option X actually resolve to for
instance Y?" without reading the merge code.
