# Enterprise Licensing (the enterprise delta)

The primary functional difference between `chef-test-kitchen-enterprise` and
upstream open-source `test-kitchen` is **Chef Licensing enforcement**. This is
implemented with the `chef-licensing` gem (plus `faraday_middleware`) and lives
under `lib/kitchen/licensing/`.

## Global configuration (`lib/kitchen/licensing/config.rb`)

At load time the module configures `chef-licensing` with Test Kitchen's product
identity:

```ruby
module Kitchen
  module Licensing
    PRODUCT_NAME         = "Test Kitchen Enterprise"
    ENTITLEMENT_ID       = "x6f3bc76-a94f-4b6c-bc97-4b7ed2b045c0"
    EXECUTABLE_NAME      = "kitchen"
    GLOBAL_LICENSE_SERVER = "https://services.chef.io/licensing"

    def self.configure_licensing
      ChefLicensing.configure do |config|
        config.chef_product_name    = PRODUCT_NAME
        config.chef_entitlement_id  = ENTITLEMENT_ID
        config.chef_executable_name = EXECUTABLE_NAME
        config.license_server_url   = GLOBAL_LICENSE_SERVER
      end
    end
  end
end

Kitchen::Licensing.configure_licensing   # invoked immediately on require
```

`configure_licensing` runs on require, so the entitlement/product/server are set
before any command executes.

## Keeping config from being clobbered (`lib/kitchen/plugin.rb`)

Many Kitchen plugins are Chef ecosystem gems that *also* depend on
`chef-licensing` and may configure it for **their own** product/entitlement when
loaded. To defend against a plugin silently overriding Kitchen's entitlement,
`Plugin.load` re-asserts Kitchen's config in an `ensure` block after every load:

```ruby
ensure
  if ChefLicensing::Config.chef_entitlement_id != Kitchen::Licensing::ENTITLEMENT_ID
    Kitchen::Licensing.configure_licensing
  end
```

This guarantees that no matter what plugin gems are pulled in, licensing checks
are evaluated against Test Kitchen Enterprise's entitlement.

## License resolution (`lib/kitchen/licensing/base.rb`)

`Kitchen::Licensing::Base` provides helpers to resolve the active license and
derive Chef install URLs from the license type:

- `get_license_keys` — pulls keys via `ChefLicensing.license_keys`; raises
  `ChefLicensing::InvalidLicense` (telling the user to run `kitchen license`) if
  none are present. Returns `[last_key, license_type, install_sh_url]`.
- `get_license_client(keys)` — queries `ChefLicensing::Api::Client.info` to
  determine the license type (free / trial / commercial).
- `install_sh_url(type, keys)` — maps the license type to the correct Omnitruck
  download endpoint so the provisioner can fetch the right Chef build:

  | type | Omnitruck host |
  | ---- | -------------- |
  | free / trial | `https://chefdownload-trial.chef.io` |
  | commercial   | `https://chefdownload-commercial.chef.io` |

## Enforcement point in the lifecycle

The check is wired into the **converge** action. In `Instance#converge_action`:

```ruby
provisioner.check_license
provisioner.call(state)          # (or the legacy_ssh_base_converge path)
```

`Provisioner::Base#check_license` is a **no-op by default**; concrete
provisioners (notably the Chef provisioners in `kitchen-chef-enterprise`)
override it to actually validate/activate a license before doing real work. This
means license enforcement gates the point where a target is actually configured
with Chef.

> **Note (verified against upstream `test-kitchen` 4.1.1):** the
> `check_license` hook itself is *not* enterprise-specific — upstream
> open-source Test Kitchen also defines `Provisioner::Base#check_license` as a
> no-op and calls it from `converge_action`. What makes this fork "enterprise"
> is the machinery that gives the hook teeth: the `licensing/` module, the
> `chef-licensing` configuration/entitlement, the `plugin.rb` re-assertion, the
> `kitchen license` command, and the gemspec dependencies. The converge-time
> call is shared plumbing, not the delta.

## The `kitchen license` command (`lib/kitchen/command/license.rb`)

Users manage licenses through a dedicated subcommand:

- `kitchen license` — fetch and persist a license (activation flow) via
  `ChefLicensing.fetch_and_persist` inside `ChefLicensing::Config.require_license_for`.
- `kitchen license list` — `ChefLicensing.list_license_keys_info`.
- `kitchen license add` — `ChefLicensing.add_license`.
- `--chef-license-key=<KEY>` — supply a key non-interactively.

Arguments are validated against the allowed `SUB_COMMANDS` (`add`, `list`) and
`OPTIONS`; unknown options print help and exit non-zero.

## Dependencies (`chef-test-kitchen-enterprise.gemspec`)

```ruby
gem.add_dependency "chef-licensing",     ">= 1.4.0", "< 2.0"
gem.add_dependency "faraday_middleware", ">= 1.0",   "< 2.0"  # required for licensing
```

## Summary

Licensing is a **cross-cutting concern** layered onto the otherwise-upstream
architecture. The genuinely enterprise-specific seams are: (1) global
`chef-licensing` config on load (`licensing/config.rb`), (2) re-assertion after
every plugin load (`plugin.rb` ensure block), the `kitchen license` command, and
the `chef-licensing`/`faraday_middleware` gemspec dependencies. The converge-time
`check_license` call is generic Test Kitchen plumbing that also exists upstream;
the enterprise value is that the licensing config above makes the overriding
provisioners actually enforce an entitlement.

## Upstream relationship & concrete divergences

> Verified against reference repo `test-kitchen` @ **4.1.1** (`context/reference-repos/test-kitchen`).

Chef Test Kitchen Enterprise uses its **own independent version numbering**, so
the enterprise version (`2.0.19`) and the upstream version (`4.1.1`) are not
comparable and say nothing about which tree is "newer" or how far they have
drifted. The meaningful comparison is at the **file/behavior level**, and there
the two have diverged in both directions — this is not a simple
"upstream + licensing" relationship.

**Files present only in this enterprise fork (`lib/kitchen/`):**

| File | Purpose |
| ---- | ------- |
| `licensing/config.rb` | Enterprise: `chef-licensing` global config |
| `licensing/base.rb` | Enterprise: license-key resolution + Omnitruck URL mapping |
| `command/license.rb` | Enterprise: `kitchen license` subcommand |
| `driver/ssh_base.rb` | **Legacy** `Driver::SSHBase` — *removed* upstream, retained here |
| `ssh.rb` | **Legacy** SSH support for the old SSHBase path — *removed* upstream, retained here |

**Files present only in upstream 4.1.1 (absent here):**

| File | Purpose |
| ---- | ------- |
| `command/logs.rb` | A `kitchen logs` subcommand present upstream |
| `provisioner/external.rb` | An `external` provisioner present upstream |

Implications for the rest of this design set:
- The `legacy_ssh_base_driver?` path and `driver/ssh_base` built-in described in
  `03-plugin-system.md` are a **deliberate retention** of legacy SSH behavior
  that upstream has since dropped — not just historical cruft.
- The `kitchen logs` command and the `external` provisioner that exist upstream
  are **not** available in this fork.
