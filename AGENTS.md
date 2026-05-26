# AGENTS.md — chef-test-kitchen-enterprise

> Agent instructions for the **Agentless Mode** feature work (Epic: CHEF-23408).
> All agentless stories target the `agentless-dev` integration branch. PRs must not target `main` directly.

---

## Repository Purpose

**chef-test-kitchen-enterprise** (`test-kitchen` local clone) is the enterprise fork of Test Kitchen — the core framework that drives instance lifecycle, config loading, CLI, transports, drivers and verifiers. The provisioner plugins (e.g., `kitchen-chef-enterprise`) hook into this framework.

Key areas of the codebase:

| Path | Description |
|------|-------------|
| `lib/kitchen/instance.rb` | Core instance lifecycle (`create`, `converge`, `setup`, `verify`, `destroy`) |
| `lib/kitchen/config.rb` | `kitchen.yml` loading and validation |
| `lib/kitchen/data_munger.rb` | YAML normalization and ERB processing |
| `lib/kitchen/provisioner/` | Base provisioner classes |
| `lib/kitchen/driver/` | Driver plugins (Dokken, Vagrant, etc.) |
| `lib/kitchen/transport/` | Transport layers (SSH, WinRM) |
| `lib/kitchen/command/` | CLI command implementations |
| `spec/` | RSpec unit tests |
| `features/` | Cucumber integration tests |
| `agenless_mode_arch/` | Architecture docs for agentless mode (note: typo in dir name is intentional — do not rename) |

---

## Agentless Mode Feature Context

### What you are building

Extensions to the TKE core to support an `agentless:` block in `kitchen.yml` and the two-node lifecycle topology. The provisioner logic lives in `kitchen-chef-enterprise`; this repo provides:

1. **Config loading**: parse and validate the `agentless:` block from `kitchen.yml`
2. **AgentlessContext**: hold remote node config and target assignment strategy
3. **RemoteNode**: data object per remote target
4. **CredentialResolver**: read `credentials.yml`, enforce OWASP warnings, mask secrets in logs, clean up on destroy
5. **TargetAssignment**: pool (Array → round-robin) and explicit (Hash keyed by instance name)
6. **Lifecycle overrides**: `kitchen create`, `kitchen setup`, `kitchen destroy` — act on source + containers only; for real nodes, log messages only
7. **State file extension**: `.kitchen/<instance>-agentless.yml` to track remote node state
8. **ERB dynamic target lists**: leverage existing ERB-in-YAML pipeline for `remote_nodes`

### kitchen.yml structure
```yaml
driver:
  name: kitchen-dokken
  chef_image: chef  # must support --t flag

provisioner:
  name: chef-infra-agentless
  data_path: test/data
  agentless:
    parallel-mode: enabled | disabled | auto
    remote_nodes:
      - name: ecommerce1
        test-kitchen-mode: container | real
        test-kitchen-image: docker.io/alpine  # container mode only
        fqdn: ecommerce1.myco.com             # optional
        endpoint: 156.43.19.90:22             # required if real
        credential-map-file: path/to/creds.yml
        credential-passing-mode: pass-by-env-var | pass-cmd-line | pass-by-creds-file
```

### credentials.yml credential source types (in scope)
- `inline` — plaintext SSH/WinRM (must warn; OWASP-compliant)
- `credential-file` — copy credentials file to source at `~/.chef/credentials`; supports passphrase encryption
- `databag` — reference databag on source node for cookbooks that shell out to infra-client

---

## Architecture: Dual-Node Topology

```
Kitchen::Instance (existing — extended, not replaced)
  ├── driver:      Dokken  (manages SOURCE container)
  ├── provisioner: ChefInfraAgentless  [in kitchen-chef-enterprise]
  │     └── agentless_context: AgentlessContext
  │           └── remote_nodes[]: RemoteNode[]
  │                 └── credential_resolver: CredentialResolver
  ├── transport:   Dokken  (TK ↔ SOURCE only)
  ├── verifier:    InSpec  (targets REMOTE node) [separate epic]
  └── state_file:  .kitchen/<instance>.yml
                    + .kitchen/<instance>-agentless.yml  (new)
```

### Full Lifecycle Sequence

```
kitchen create:
  → Dokken spins up SOURCE container
  → If remote_node.mode == :container → Dokken also spins up remote containers
  → If remote_node.mode == :real      → log "Real node; skipping create"

kitchen converge:
  → CredentialResolver resolves secrets from credentials.yml
  → Upload credentials to source (~/.chef/credentials)
  → Upload cookbooks to source
  → Run: chef-client --target <remote> --runlist <list>  (on source container)
  → Capture output on source, stream to TKE console

kitchen destroy:
  → Remove credentials from source container
  → Dokken stops source container
  → If remote_node.mode == :container → Dokken stops remote containers
  → If remote_node.mode == :real      → log "Real node; skipping destroy"
```

---

## Key New Classes (to be created in this repo)

| Class | File | Purpose |
|-------|------|---------|
| `Kitchen::AgentlessContext` | `lib/kitchen/agentless_context.rb` | Holds RemoteNode list + assignment strategy |
| `Kitchen::RemoteNode` | `lib/kitchen/remote_node.rb` | Data object for one remote target |
| `Kitchen::CredentialResolver` | `lib/kitchen/credential_resolver.rb` | Reads credentials.yml, enforces warnings, masks |
| `Kitchen::TargetAssignment::Pool` | `lib/kitchen/target_assignment/pool.rb` | Round-robin from Array of nodes |
| `Kitchen::TargetAssignment::Explicit` | `lib/kitchen/target_assignment/explicit.rb` | Hash keyed by instance name |

---

## File/Naming Conventions

- All new kitchen core files go in `lib/kitchen/`
- Support subdirectories: `lib/kitchen/agentless/`, `lib/kitchen/target_assignment/`
- Spec files mirror source: `spec/kitchen/agentless_context_spec.rb`, etc.
- Always include `# frozen_string_literal: true` at top of every Ruby file
- Apache 2.0 license header on every new file
- Rubocop compliant — run `bundle exec rubocop` before committing

---

## Coding Conventions

- RSpec for unit tests (not Minitest — this repo uses RSpec)
- Cucumber for integration tests in `features/`
- Use `Kitchen::UserError` for user-facing errors
- Log via `info`, `debug`, `warn` on kitchen logger (not `puts` or `$stdout`)
- Secret masking: intercept logger output, never log credential values
- ERB template processing for `remote_nodes` uses existing `DataMunger` pipeline — do not bypass it
- Config validation: add schema validation alongside `config.rb` / `data_munger.rb` patterns

---

## Testing

```bash
# Unit tests (RSpec)
bundle exec rspec

# Integration tests (Cucumber)
bundle exec cucumber

# Lint
bundle exec rubocop --no-color

# All unit tests
bundle exec rake spec
```

- New code requires corresponding RSpec spec files under `spec/kitchen/`
- Spec files must mirror `lib/` structure
- Use `RSpec` doubles/mocks (not Mocha — that's only in `kitchen-chef-enterprise`)

---

## Architecture Docs in This Repo

The `agenless_mode_arch/` directory (note: intentional typo in dirname) contains detailed architecture docs:

| File | Content |
|------|---------|
| `01-overview.md` | Problem, solution, personas, acceptance criteria |
| `02-current-architecture.md` | Current agent-based architecture |
| `03-agentless-architecture.md` | New dual-node topology, sequence diagrams |
| `04-configuration-reference.md` | Full kitchen.yml and credentials.yml schema |
| `05-credential-management.md` | Credential types, OWASP warnings, masking |
| `06-lifecycle-flow.md` | Detailed lifecycle flow per command |
| `07-target-node-assignment.md` | Pool vs explicit assignment strategies |
| `08-risks-and-issues.md` | Known risks and open questions |

**Always read the relevant arch doc before implementing a story.**

---

## Branch & PR Rules for Agentless Stories

| Rule | Value |
|------|-------|
| Integration branch | `agentless-dev` |
| Story branch format | `CHEF-XXXXX-<short-description>` |
| PR target | `agentless-dev` (NOT `main`) |
| PR title format | `[CHEF-XXXXX] <short description>` |
| PR labels | Must include `ai-assisted` label |
| Final merge to `main` | Only after full epic sign-off |

**Never raise a PR directly to `main` for agentless work.**

---

## Story Branch Map

| Story | Branch name |
|-------|-------------|
| CHEF-27350 | `CHEF-27350-provision-source-container` |
| CHEF-27351 | `CHEF-27351-agentless-call-real-mode` |
| CHEF-27352 | `CHEF-27352-agentless-call-container-mode` |
| CHEF-27353 | `CHEF-27353-collect-forward-results` |
| CHEF-27354 | `CHEF-27354-secret-cleanup-destroy` |
| CHEF-34459 | `CHEF-34459-implement-parallel-runs` |
| CHEF-34937 | `CHEF-34937-erb-dynamic-target-lists` |
| CHEF-27346 | `CHEF-27346-mask-secrets-warn-insecure` |
| CHEF-27345 | `CHEF-27345-document-agentless-mode` |

---

## Related Resources

- [Epic CHEF-23408](https://progresssoftware.atlassian.net/browse/CHEF-23408)
- [Architecture docs](./agenless_mode_arch/)
- [Miro architecture diagram](https://miro.com/app/board/uXjVJ4PKUKs=/?moveToWidget=3458764644736269412&cot=14)
- [kitchen-chef-enterprise repo](https://github.com/chef/kitchen-chef-enterprise) — provisioner plugin (agentless logic lives there)
