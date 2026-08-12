---
applyTo: "lib/kitchen/command/list.rb,lib/kitchen/command/destroy.rb,lib/kitchen/provisioner/base.rb"
---

# Extending Agentless Support in TKE Core vs. KCAI

## Architecture note (post CHEF-27348 / CHEF-23408 rewrite)

Earlier generations of this epic (Waves 1–14) put agentless-specific config
parsing, credential resolution, and remote-node modeling directly into TKE
core (`lib/kitchen/agentless/`, `lib/kitchen/agentless_context.rb`,
`lib/kitchen/remote_node.rb`, etc). **That code has been deleted
(CHEF-27348).** Do not resurrect this pattern.

The current architecture is:

| Repo | Owns |
|------|------|
| `chef-test-kitchen-enterprise` (TKE core, this repo) | Generic driver/provisioner/verifier extension points only. No knowledge of "agentless" as a concept. |
| `chef/kitchen-agentless` (KCAI) | Everything agentless-specific: the `agentless:` config block, `AgentlessContext`, `RemoteNode`, credential resolution, the `Kitchen::Driver::Agentless`, `Kitchen::Provisioner::ChefInfraAgentless`, and `Kitchen::Verifier::InspecAgentless` classes. |

If you're asked to add a new field to the `agentless:` block in `kitchen.yml`,
**that work belongs in KCAI**, not here. See the equivalent
`agentless-config-extension.instructions.md` in the KCAI repo (if present) —
or just follow the pattern below there.

## What TKE core actually owns for this epic

TKE core changes for CHEF-23408 are strictly limited to generic hooks any
driver could use — they must contain zero agentless-specific logic:

| File | What it exposes | Story |
|------|------------------|-------|
| `lib/kitchen/command/list.rb` | Generic `driver.source_info` hook — if a driver responds to `#source_info`, an extra section is rendered above the instances table (works for *any* driver, not just agentless) | CHEF-36826 (done) |
| `lib/kitchen/command/destroy.rb` | Generic `--driver-option key=value` passthrough so any plugin can receive destroy-time flags | CHEF-36826 (done) |
| `lib/kitchen/provisioner/base.rb` | No agentless-specific config — `#agentless_mode?` and `default_config :agentless` were removed here (CHEF-27348, done) | CHEF-27348 (done) |

If a change request for this epic touches any file other than the three
above, stop and confirm it isn't actually KCAI-plugin work that was
misdirected at this repo.

## Adding a new generic driver hook (the TKE-core pattern to follow)

Example: adding a new hook so any driver can contribute a status line to
`kitchen list`.

1. In the relevant `lib/kitchen/command/*.rb`, check `respond_to?` on the
   driver/provisioner/verifier rather than hardcoding a class name:

```ruby
# lib/kitchen/command/list.rb — generic, agentless-unaware
def print_table(instances)
  source = instances.first&.driver&.respond_to?(:source_info) &&
           instances.first.driver.source_info
  print_source_section(source) if source
  # ... existing instances table rendering ...
end
```

2. Document the expected return shape (e.g. a Hash with specific keys) in a
   code comment, since TKE core has no interface/protocol enforcement beyond
   `respond_to?`.
3. Add a spec in `spec/kitchen/command/*_spec.rb` using a stub/double that
   responds to the new method — do not depend on any real plugin.
4. Add a regression test for the case where the driver does **not** respond
   to the hook (must degrade gracefully, no `NoMethodError`).

## Extending the `agentless:` config block itself (KCAI repo, for reference)

Even though this work happens in KCAI, it's useful context when reviewing
cross-repo changes. Key KCAI files:

| File | Role |
|------|------|
| `lib/kitchen/driver/agentless.rb` | Parses `agentless:` config, manages source-node lifecycle |
| `lib/kitchen/provisioner/chef_infra_agentless.rb` | chef-client target-mode invocation, credential/endpoint resolution |
| `lib/kitchen/verifier/inspec_agentless.rb` | InSpec target-mode invocation — **duplicates**, not inherits, the provisioner's credential/endpoint resolution |

When adding a new `agentless:` field (e.g. a new `remote_nodes[].transport`
option), remember:
- Both the provisioner and verifier likely need the change — they are
  separate classes with parallel logic (see
  `bug-fix-workflow.instructions.md`'s note on this being a recurring bug
  source).
- Consider all **three target-provisioning styles** (real-mode static host,
  ephemeral Docker, ephemeral EC2 with a named keypair) when adding to the
  credential-resolution chain — see `bug-fix-workflow.instructions.md` for
  the full priority order and rationale.
- Add regression tests for both real-mode and ephemeral-mode behavior; a
  test suite that only covers one mode will miss the class of bugs this repo
  has repeatedly hit (stale credential-map-file hijacking, missing driver
  state fallback, missing `instance.transport` fallback).

## Running TKE core tests

```bash
cd /path/to/chef-test-kitchen-enterprise
bundle exec rake unit                            # Minitest unit suite
bundle exec rake features                        # Cucumber integration suite
bundle exec cookstyle --chefstyle lib/ spec/     # lint
```

## Critical rules

- TKE core must have **zero** references to "agentless" as a concept —
  only generic `respond_to?`-based extension points.
- Never call `instance.state_file` from outside `Instance` — it's private;
  use the `state` hash passed into lifecycle methods.
- Do not modify `lib/kitchen/version.rb` or `CHANGELOG.md` — managed by Expeditor.
