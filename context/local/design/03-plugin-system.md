# Plugin System

Test Kitchen's extensibility is its defining feature. The four primary plugin
types — **Driver, Provisioner, Transport, Verifier** — plus **Lifecycle Hooks**
share a common base architecture, are configured with the same DSL
(`Configurable`), and are loaded dynamically by naming convention so third-party
plugins ship as independent gems.

## Plugin type responsibilities

| Type          | Base class                       | Built-ins in this repo                | Notable external gems |
| ------------- | -------------------------------- | ------------------------------------- | --------------------- |
| Driver        | `Kitchen::Driver::Base`          | `dummy`, `exec`, `proxy`, `ssh_base`  | `kitchen-ec2`, `kitchen-vagrant`, `kitchen-dokken`, `kitchen-vcenter`, `kitchen-azurerm`, `kitchen-google`, `kitchen-hyperv` |
| Provisioner   | `Kitchen::Provisioner::Base`     | `dummy`, `shell`                      | `kitchen-chef-enterprise` |
| Transport     | `Kitchen::Transport::Base`       | `dummy`, `exec`, `ssh`, `winrm`       | `kitchen-dokken` transport |
| Verifier      | `Kitchen::Verifier::Base`        | `dummy`, `shell`, `busser`            | `kitchen-inspec` |
| Lifecycle     | `Kitchen::LifecycleHooks`        | built-in local/remote command hooks   | — |

> The default Chef provisioner and the InSpec verifier live in **separate gems**
> (see `Gemfile`), so converge/verify behavior depends on those gems being
> installed. The core repo ships only minimal built-ins (`dummy`, `shell`,
> `exec`, `busser`).

## Common base class hierarchy

```
Kitchen::Configurable  (mixin: config DSL, defaults, validation, diagnose)
Kitchen::Logging       (mixin: info/debug/error helpers)
        |
Kitchen::Plugin::Base  (class methods: no_parallel_for / serial_actions)
        |
   +----+----------+-----------------+--------------+
Driver::Base   Provisioner::Base   Transport::Base   Verifier::Base
```

Every plugin instance is constructed with a config hash and later has
`finalize_config!(instance)` called on it by the owning `Instance`, which
back-references the `instance` into the plugin (giving it access to logger,
suite, platform, transport, etc.) and resolves defaults/validations.

## Dynamic loading (`lib/kitchen/plugin.rb`)

`Kitchen::Plugin.load(type, plugin_name, config)` resolves a plugin by
**convention**, not registration:

1. `require "kitchen/<type>/<plugin_name>"` — e.g. `kitchen/driver/ec2`.
2. Constantize: `Kitchen::Driver.const_get("Ec2")`.
3. Instantiate with config; on first load, call `verify_dependencies` so the
   plugin can fail fast if a system dependency is missing.

Failure handling is user-friendly:
- `LoadError` -> scans `$LOAD_PATH` via `plugins_available` and suggests
  near-matches ("Did you mean: ec2, vagrant?") plus a Gemfile reminder.
- `NameError` -> surfaced as a `ClientError`.

`plugins_available(type)` discovers plugins by globbing `kitchen/<type>/*.rb`
across every load path, keeping files that define a subclass (`class X < ...`)
and excluding `base`.

### Enterprise hook in loading

The `ensure` block of `Plugin.load` re-applies Kitchen's licensing config if a
just-loaded plugin gem changed `ChefLicensing::Config.chef_entitlement_id`,
preventing a plugin's own `chef-licensing` setup from clobbering Kitchen's
entitlement. See `06-enterprise-licensing.md`.

## The Configurable DSL (`lib/kitchen/configurable.rb`)

Class-level methods define behavior; instances resolve values lazily.

| DSL method | Purpose |
| ---------- | ------- |
| `default_config :attr, value` (or block) | Provide a default; block form receives the object for dynamic defaults. Merges with superclass defaults. |
| `required_config :attr` (or block) | Enforce a non-blank value; default validation raises `UserError` if blank. Block form allows custom validation. |
| `expand_path_for :attr` | Auto-expand a config value to an absolute local path. Supports conditional block form. |
| `deprecate_config_for :attr, msg` | Emit a deprecation warning for an attribute. |
| `plugin_version :version` | Record the plugin's version for diagnostics. |

Instance-level helpers:
- `config[:attr]` — resolved value (default applied, path expanded, lazily
  computed via `LazyHash`).
- `validate_config!` — runs all registered validations; called during
  `finalize_config!`.
- `diagnose` / `diagnose_plugin` — emit merged config and plugin metadata for
  `kitchen diagnose`.

## Plugin API versioning

Drivers and provisioners declare the API contract they implement:

```ruby
kitchen_driver_api_version 2
kitchen_provisioner_api_version 2
```

This lets the core evolve while detecting/adapting to older plugins. The
Instance layer also has an explicit **legacy SSH driver** path
(`legacy_ssh_base_driver?`) that special-cases pre-API-v2 drivers built on
`Driver::SSHBase`, routing converge/setup/verify/login through legacy shims
instead of the modern Transport abstraction.

## Concurrency contract (`Kitchen::Plugin::Base`)

```ruby
no_parallel_for :create, :destroy
```

Registers actions that must not run concurrently for this plugin. Only the five
lifecycle actions are valid; anything else raises `ClientError`. The Instance
layer reads `serial_actions` to build a per-class mutex and serialize those
actions across all instances using the plugin (see `02-lifecycle-and-state.md`).

## Writing a new plugin (shape)

```ruby
module Kitchen
  module Driver
    class MyCloud < Kitchen::Driver::Base
      kitchen_driver_api_version 2
      plugin_version Kitchen::VERSION

      default_config :region, "us-east-1"
      required_config :api_token

      no_parallel_for :create, :destroy

      def create(state)
        return if state[:server_id]        # idempotent
        info("Creating server...")
        state[:server_id] = provision!(config[:region])
        state[:hostname]  = lookup_ip(state[:server_id])
      end

      def destroy(state)
        return unless state[:server_id]
        info("Destroying server...")
        teardown!(state[:server_id])
        state.delete(:server_id)
      end
    end
  end
end
```

Conventions: actions receive and mutate the `state` hash; actions are
**idempotent** (guard on state); user-facing failures raise `UserError`; and the
box's connection details are written into `state` for the transport to reuse.
