---
applyTo: "**/*"
---

# Bug Fix Workflow for Agentless Mode (KCAI + TKE core)

## How to read a failure

- `.kitchen/logs/kitchen.log` — top-level command log.
- `.kitchen/logs/<instance>.log` — per-instance log, usually has the real stack trace.
- **Check `KITCHEN_YAML` first.** If the error mentions a host/sub-driver that
  doesn't match the `kitchen.yml` you're looking at, the user is very likely
  running with `KITCHEN_YAML=some-other.yml kitchen ...`. Always ask or check
  the shell history/env before assuming a code regression.
- **Check for stale `.kitchen/*.yml` state files.** If a user switches between
  different kitchen configs (e.g. Docker-ephemeral vs. `kitchen.ec2.yml`)
  without running `kitchen destroy` first, `.kitchen/<instance>.yml` and
  `.kitchen/<source>.yml` retain the *previous* config's driver/server-id/host,
  producing confusing "wrong host" or "credentials file not found" errors that
  look like code bugs but are actually just leftover local state. Compare file
  mtimes/content against the currently active kitchen.yml before debugging further.
  Fix: `rm .kitchen/<instance>.yml .kitchen/<source>.yml` and re-run `kitchen create`.

## Credential / endpoint resolution (the most common source of bugs)

KCAI must support **three distinct target-provisioning styles**, and the
resolution chain in both `chef_infra_agentless.rb` (provisioner) and
`inspec_agentless.rb` (verifier) must handle all three without one silently
clobbering another:

1. **Real-mode static hosts** — credentials come from the credential-map-file
   (`credentials.yml`, keyed by instance name) or
   `agentless.remote_nodes[name].transport`. Only consult these when
   `real_mode?` is true — checking them unconditionally lets a **stale
   credential-map-file entry hijack an ephemeral target's real, valid
   credentials** (this exact bug shipped once — see commit `4a5a9b0`/`5b40e44`).
2. **Ephemeral Docker targets** — `kitchen-docker` self-generates an SSH
   keypair (`.kitchen/docker_id_rsa`) and sets `state[:ssh_key]`, defaulting
   username to `"kitchen"` — but it **never sets `state[:username]`
   itself**. Credentials live in **driver state**.
3. **Ephemeral EC2 (or any driver using a pre-existing named keypair)** — the
   sub-driver does **not** generate dynamic credentials in state at all. The
   user configures username/ssh_key via kitchen.yml's **standard Test Kitchen
   `transport:` block** (top-level/suite/platform), resolved by TK into
   `instance.transport`. If this fallback is missing, username silently
   defaults to `"root"` and no key/password is found — target-credential
   provisioning is skipped entirely and chef-client/InSpec fail looking for a
   credentials file that was never written.

**Correct resolution priority** (for username/ssh_key/password, in each of
`resolve_target_username`/`resolve_target_ssh_key`/`resolve_target_password`):

```
credential-map-file (real_mode? only)
  → agentless.remote_nodes[name].transport
  → top-level node config
  → driver state                                    (Docker's dynamic creds)
  → instance's own resolved transport config          (instance.transport.diagnose)
  → hardcoded default ("root" / nil)
```

**Driver state must be checked before `instance.transport`.** TK's own
`Kitchen::Transport::Ssh` sets `default_config :username, "root"`, so
`instance.transport.diagnose[:username]` is **always truthy** even when the
user never configured it explicitly. If checked before driver state, it would
always shadow Docker's real, dynamically-assigned username. `ssh_key`/`password`
don't have this problem since their TK transport defaults are `nil` — but keep
the same ordering for consistency and to support all three styles uniformly.

`instance.transport.diagnose` returns a Hash of fully-resolved config
(symbol-keyed); `ssh_key` may come back as a single path or an `Array` —
normalize with `Array(...).first`.

## Common failure patterns and fixes

### `Net::SSH::AuthenticationFailed` / wrong username against an ephemeral Docker target

Check `credential_file_ssh_entry` isn't being consulted unconditionally — gate
it to `real_mode?` only. See "Credential / endpoint resolution" above.

### `Your SSH Agent has no keys added, and you have not specified a password or a key file` (InSpec verify)

The verifier has its **own, separate** copy of the credential-resolution logic
(`inspec_agentless.rb` does not inherit from the provisioner). A fix applied
to the provisioner's `resolve_target_*` methods must be mirrored in the
verifier's — they are easy to forget since they look similar but are not DRY'd
up. Also check `decorate_credential_manager` builds the InSpec `--user`
`--password` `--key_files` CLI args from `resolve_target_username`/
`resolve_target_ssh_key`/`resolve_target_password`, not directly from
`resolved_credentials_for` (which is real-mode-only and returns nothing for
ephemeral targets with no credential-map-file entry).

### `ECONNREFUSED` connecting to `127.0.0.1:<port>` (verify against a Docker target)

The verifier's `resolve_target_endpoint` is missing the Docker-internal-bridge
-IP resolution the provisioner already has. From *inside* the agentless-source
container, the host-mapped port (`localhost:<port>`) is unreachable — you must
resolve the container's internal IP via `docker inspect` (see
`docker_internal_ip` in `chef_infra_agentless.rb`) whenever `state[:container_id]`
is present, and port back to plain `22` instead of the host-mapped port.

### `ArgumentError: Credentials file specified for target mode does not exist: '~/.chef/target_credentials'`

Target-credential provisioning was silently skipped because username/ssh_key
resolution fell through to nothing usable (commonly: an ephemeral EC2 target
whose only credential source is the standard `transport:` block — see
"Credential / endpoint resolution" above; the `instance_transport_config`
fallback fixes this specific case).

### `cannot load such file -- license_acceptance/acceptor`

The `license_acceptance` gem isn't available on the *source* node where
chef-client/InSpec actually runs. This is an environment/install issue on the
agentless-source, not a KCAI code bug — check the Chef Infra Client / InSpec
install strategy and version on the source node.

### InSpec install fails with `dpkg: error: requested operation requires superuser privilege`

The InSpec omnitruck installer needs to run as root on the source node.
Check `install_strategy` / the install command is prefixed with `sudo` (or run
as root) when installing a specific/pinned InSpec version rather than relying
on a pre-baked image.

### InSpec stuck at an interactive "License ID Validation" prompt

InSpec (Chef License) needs `CHEF_LICENSE=accept` (and `CHEF_LICENSE_KEY=...`
if a commercial/free-tier key is configured) in the environment for **every**
`inspec exec` invocation, not just chef-client. Check both the
provisioner's and verifier's command-building code set this env var
consistently — a mismatch (one sets it, the other doesn't) causes exactly this
symptom on `kitchen verify` after `kitchen converge` succeeds.

### `NoMethodError` / `undefined method` calling a private TKE method

Common culprit: calling `instance.state_file` directly. Use the `state` hash
passed into lifecycle methods instead.
```ruby
# WRONG:
instance.state_file.read["some_key"]
# CORRECT:
state[:some_key]
```

### Shell operators not working (`|`, `>`, `&&`) when executing on the source/target

Docker exec / Train's SSH backend calls the command directly — **no shell**.
Wrap multi-command strings in `sh -c '...'`:
```ruby
# WRONG:
conn.execute("echo #{encoded} | base64 -d > /root/.ssh/key")
# CORRECT:
conn.execute("sh -c 'echo #{encoded} | base64 -d > /root/.ssh/key'")
```

### `train-docker gem not found` / `Docker URI not supported`

`docker://container-name` URIs require the `train-docker` gem, which is not
bundled by default. Prefer SSH transport (`ssh://user@ip:22`) for
container-mode targets instead of a raw `docker://` URI.

## Debug commands

```bash
# See what's on the agentless-source container/host
docker exec <source-container-name> ls /tmp/kitchen-sandbox/
docker exec <source-container-name> cat ~/.chef/target_credentials

# Confirm which kitchen.yml is actually active
echo $KITCHEN_YAML
ls -la .kitchen/*.yml   # check mtimes against the active config

# Full kitchen debug
bundle exec kitchen --log-level debug converge 2>&1 | tee /tmp/kitchen-debug.log
```

## After fixing

Fix both the provisioner (`chef_infra_agentless.rb`) **and** the verifier
(`inspec_agentless.rb`) if the bug is in credential/endpoint resolution — they
are separate classes with duplicated logic, not shared via inheritance.

```bash
bundle exec rake unit                            # must be 0 failures
bundle exec cookstyle --chefstyle lib/ spec/     # must be 0 new offenses
bundle exec kitchen destroy && bundle exec kitchen converge && bundle exec kitchen verify  # end-to-end
```

Test against **all three provisioning styles** when the fix touches
credential/endpoint resolution: real-mode static host, ephemeral Docker
target, ephemeral EC2 target (named keypair via standard `transport:` block).
