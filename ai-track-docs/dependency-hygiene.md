# Dependency Hygiene Notes (Ex7)

## Scope
This note captures critical dependency surfaces and conservative constraint proposals for this repository.

- Primary manifests:
  - `Gemfile`
  - `chef-test-kitchen-enterprise.gemspec`
  - `test-kitchen.gemspec`

## Critical Dependencies
### Runtime (gemspec)
- `chef-licensing` (`>= 1.4.0`, `< 2.0`)
- `chef-utils` (`>= 16.4.35`)
- `mixlib-shellout` (`>= 1.2`, `< 4.0`)
- `thor` (`>= 0.19`, `< 2.0`)
- `net-ssh` (`>= 2.9`, `< 8.0`)
- `net-scp` (`>= 1.1`, `< 5.0`)
- `net-ssh-gateway` (`>= 1.2`, `< 3.0`)
- WinRM stack:
  - `chef-winrm` (`>= 2.5.0`, `< 3.0`)
  - `chef-winrm-elevated` (`>= 1.0`, `< 2.0`)
  - `chef-winrm-fs` (`>= 1.0`, `< 2.0`)
- SSH key support:
  - `ed25519` (`>= 1.2`, `< 2.0`)
  - `bcrypt_pbkdf` (`>= 1.0`, `< 2.0`)

### Development and Test (Gemfile)
- Explicit exclusion: `net-ssh != 7.3.1` (known regression comment in `Gemfile`)
- Tooling bounds:
  - `cookstyle >= 8.2, < 9.0`
  - `cucumber >= 9.2, < 11`
  - `minitest >= 5.3, < 7.0`
  - `mocha >= 2.0, < 4.0`
- Integration plugin dependencies include many `>=` only constraints and two git-branch sources (`kitchen-dokken`, fallback `kitchen-chef-enterprise`).

## Minimal Constraint Proposals (No Major Upgrades)
These are proposed guardrails, intentionally conservative and not applied in this Ex7 change:

1. Add upper bounds for currently open-ended runtime dep:
   - `chef-utils`: propose `< 19.0`.
   - Rationale: prevent silent adoption of future major API changes.

2. Add upper bounds for open-ended integration dependencies in `Gemfile`:
   - `chef-cli`: propose `< 8.0`
   - `berkshelf`: propose `< 10.0`
   - `kitchen-inspec`: propose `< 4.0`
   - `chef`: propose `< 21.0`
   - Rationale: reduce breakage risk from major bumps while preserving minor/patch updates.

3. Prefer tagged release constraints over `branch: main` where possible:
   - `kitchen-dokken`
   - fallback `kitchen-chef-enterprise`
   - Rationale: improve reproducibility and lower drift risk.

## Current Lockfile Baseline (Observed)
Snapshot from `Gemfile.lock` at Ex7 time:
- `chef-licensing`: 1.4.1
- `chef-utils`: 19.2.12
- `chef-winrm`: 2.5.0
- `cucumber`: 10.2.0
- `faraday_middleware`: 1.2.1
- `minitest`: 5.27.0
- `mixlib-shellout`: 3.3.9
- `mocha`: 3.1.0
- `net-ssh`: 7.3.0
- `thor`: 1.4.0

## Low-Risk Hygiene Checklist
- Keep regression excludes documented inline (for example `net-ssh != 7.3.1`).
- Keep major-version upper bounds for runtime protocol layers (SSH/WinRM).
- Revisit proposals when lockfile or CI compatibility matrix changes.

## Verification Commands
```bash
bundle install
bundle exec rake unit
bundle exec ruby -I spec spec/kitchen/verifier/dummy_spec.rb
```

For dependency-only review (no upgrades):
```bash
bundle outdated
```
