---
title: Chef Infra Agentless
slug: agentless
menu:
  docs:
    parent: provisioners
    weight: 10
---

The `chef-infra-agentless` provisioner enables **Agentless Mode** in Test Kitchen Enterprise — allowing you to develop and test Chef cookbooks against remote nodes **without installing Chef Infra Client on the target**. This is the primary mode for testing edge devices, IoT targets, and any system where agent installation is prohibited.

Agentless Mode uses a dual-node topology: a **source container** (where Chef Infra Client runs) plus one or more **remote nodes** (the actual targets). Chef is invoked via `chef-client --target` (Target Mode) from the source container.

> **Plugin requirement:** The `chef-infra-agentless` provisioner ships as a separate gem (`kitchen-chef-infra-agentless`) and is not bundled with Test Kitchen Enterprise by default. Install it before use:
>
> ```bash
> chef gem install kitchen-chef-infra-agentless
> ```

---

## Quick Start

```yaml
---
driver:
  name: dokken
  chef_image: chef/chef   # must be Chef 18+ with --target support

transport:
  name: dokken

provisioner:
  name: chef-infra-agentless
  data_path: test/data
  agentless:
    parallel-mode: disabled
    remote_nodes:
      - name: web01
        test-kitchen-mode: container
        test-kitchen-image: dokken/ubuntu-24.04
        credential-map-file: test/credentials.yml
        credential-passing-mode: pass-by-creds-file

platforms:
  - name: ubuntu-24.04

suites:
  - name: default
    run_list:
      - recipe[my_cookbook::default]
```

---

## Architecture

In Agentless Mode, `kitchen.yml` defines a two-node topology:

```
Your Workstation (kitchen CLI)
         │
         │  SSH / Dokken transport
         ▼
  SOURCE CONTAINER
  (Chef 18+ installed)
         │
         │  chef-client --target  (SSH or WinRM)
         ▼
  REMOTE NODE(s)
  (no Chef agent installed)
```

The **source container** is managed by the Dokken driver. TKE provisions it with credentials and cookbooks, then invokes `chef-client --target <remote>` to converge the remote node. Run output is captured on the source and forwarded to your terminal.

---

## `kitchen.yml` Configuration

### `provisioner:` section

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `name` | String | **Yes** | — | Must be `chef-infra-agentless` |
| `data_path` | String | No | — | Path to data bags, environments, and other Chef data |
| `agentless` | Hash | **Yes** | — | Agentless configuration block (see below) |

### `agentless:` block

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `parallel-mode` | String | No | `disabled` | Multi-node execution mode. See [Parallel Mode](#parallel-mode) |
| `remote_nodes` | Array or Hash | **Yes** | — | Remote target definitions. See [Target Node Assignment](#target-node-assignment) |

### `remote_nodes[]` item keys

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | String | **Yes** | Unique node identifier; used to look up entries in `credentials.yml` |
| `test-kitchen-mode` | String | **Yes** | `container` — spin up a Docker container; `real` — target an existing node |
| `test-kitchen-image` | String | If `container` | Docker image to use for the simulated remote node |
| `endpoint` | String | If `real` | Connection endpoint in `<host>:<port>` format (e.g. `10.0.0.5:22`) |
| `fqdn` | String | No | Fully-qualified domain name; used as the Chef node name |
| `transport` | String | No | `ssh` or `winrm`; overrides the transport declared in `credentials.yml` |
| `credential-map-file` | String | **Yes** | Path to `credentials.yml` for this node |
| `credential-passing-mode` | String | **Yes** | `pass-by-creds-file` \| `pass-cmd-line` \| `pass-by-env-var` |

---

## `credentials.yml` Reference

Each remote node references a `credentials.yml` file. The file holds credential entries keyed by node `name`.

### Credential source types

#### `inline` — Plaintext credentials (development only)

```yaml
remote-nodes:
  - name: web01
    credential-source-type: inline
    transport: ssh
    ssh-user: ec2-user
    ssh-pass: "s3cr3t"    # ⚠️  TKE will emit an OWASP plaintext warning
```

> **Security warning:** Inline plaintext credentials trigger an OWASP-compliant warning at every converge. Do not use in production or CI pipelines with shared logs.

#### `credential-file` — Copy credentials file to source container

```yaml
remote-nodes:
  - name: web01
    credential-source-type: credential-file
    transport: ssh
    credential-source: test/chef-credentials.toml
    # Optional passphrase encryption — TKE will prompt interactively
    # or read KITCHEN_CREDENTIAL_PASSPHRASE environment variable
```

The file is copied to `~/.chef/credentials` on the source container during `kitchen converge` and removed during `kitchen destroy`.

#### `databag` — Resolve credentials from a Chef data bag on the source node

```yaml
remote-nodes:
  - name: web01
    credential-source-type: databag
    transport: ssh
    credential-source: myorg.ssh_credentials    # org.databag-name
    credential-name: web01/ssh_key              # key path within the databag
```

#### WinRM example

```yaml
remote-nodes:
  - name: winhost01
    credential-source-type: inline
    transport: winrm
    winrm-user: Administrator
    winrm-pass: "W1nRM@pass"   # ⚠️  triggers plaintext warning
```

### `credentials.yml` key reference

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | String | **Yes** | Must match the `name` in `kitchen.yml` `remote_nodes` |
| `credential-source-type` | String | **Yes** | `inline` \| `credential-file` \| `databag` |
| `transport` | String | **Yes** | `ssh` or `winrm` |
| `ssh-user` | String | If `inline` + SSH | SSH username |
| `ssh-pass` | String | If `inline` + SSH | SSH password |
| `winrm-user` | String | If `inline` + WinRM | WinRM username |
| `winrm-pass` | String | If `inline` + WinRM | WinRM password |
| `credential-source` | String | If `credential-file` or `databag` | File path or `org.databag-name` |
| `credential-name` | String | If `databag` | Key path within the data bag |

---

## Target Node Assignment

Agentless Mode supports two strategies for assigning remote nodes to Test Kitchen instances (suite × platform combinations).

### Pool Mode (Array)

Define `remote_nodes` as an Array. Nodes are assigned to instances in round-robin order. Multiple instances share the pool.

```yaml
agentless:
  remote_nodes:
    - name: web01
      test-kitchen-mode: container
      test-kitchen-image: dokken/ubuntu-24.04
      credential-map-file: test/credentials.yml
      credential-passing-mode: pass-by-creds-file
    - name: web02
      test-kitchen-mode: real
      endpoint: 10.0.0.50:22
      credential-map-file: test/credentials.yml
      credential-passing-mode: pass-cmd-line
```

### Explicit Assignment Mode (Hash)

Define `remote_nodes` as a Hash keyed by instance name (`<suite>-<platform>`). Each instance gets a dedicated node.

```yaml
agentless:
  remote_nodes:
    default-ubuntu-24.04:
      name: web01
      test-kitchen-mode: container
      test-kitchen-image: dokken/ubuntu-24.04
      credential-map-file: test/credentials.yml
      credential-passing-mode: pass-by-creds-file
    default-almalinux-9:
      name: edge01
      test-kitchen-mode: real
      endpoint: 10.0.0.51:22
      credential-map-file: test/credentials.yml
      credential-passing-mode: pass-cmd-line
```

---

## Lifecycle Behaviour

Agentless Mode changes how each `kitchen` command behaves:

| Command | Agentless behaviour |
|---------|---------------------|
| `kitchen create` | Spins up source container; spins up container-mode remote nodes; logs a message for real nodes (no action taken) |
| `kitchen converge` | Uploads cookbooks/data to source; resolves + provisions credentials; runs `chef-client --target <remote>` from source; captures and forwards output |
| `kitchen setup` | Runs setup on source container; logs a no-op message for real remote nodes |
| `kitchen verify` | *(Future epic)* — InSpec will target the remote node |
| `kitchen destroy` | Removes credentials from source; destroys container-mode remotes; logs a message for real nodes (not modified); tears down source container |
| `kitchen test` | Full lifecycle: create → converge → setup → verify → destroy |
| `kitchen login` | Opens a shell into the **source** container |

> **Real nodes are never created or destroyed by TKE.** TKE only converges them. The converge state applied during a session remains active on the real node after `kitchen destroy`.

---

## Parallel Mode

When `parallel-mode: enabled`, TKE converges all remote nodes concurrently using a thread-per-node model. Log output is serialised per node (no interleaving).

```yaml
agentless:
  parallel-mode: enabled   # disabled | enabled | auto
```

| Value | Behaviour |
|-------|-----------|
| `disabled` | Sequential convergence (default; safest) |
| `enabled` | All nodes converge concurrently |
| `auto` | Let chef-client decide based on available resources |

> Requires Chef Infra Client 18+ with parallel target mode support.

---

## WinRM / Windows Targets

Windows remote nodes are supported via the WinRM transport. Specify `transport: winrm` in `credentials.yml` or directly on the remote node in `kitchen.yml`.

```yaml
# kitchen.yml
agentless:
  remote_nodes:
    - name: winhost01
      test-kitchen-mode: real
      endpoint: 10.0.0.10:5985
      transport: winrm
      credential-map-file: test/credentials.yml
      credential-passing-mode: pass-by-creds-file
```

```yaml
# credentials.yml
remote-nodes:
  - name: winhost01
    credential-source-type: inline
    transport: winrm
    winrm-user: Administrator
    winrm-pass: "MyPassword!"
```

WinRM default port: `5985`. Set `endpoint` explicitly if your server uses a different port.

---

## ERB Dynamic Target Lists

TKE processes ERB in `kitchen.yml` before parsing. This allows dynamic remote node lists built from environment variables or external files — useful in CI pipelines where targets change per run.

### Targets from an environment variable

```yaml
agentless:
  remote_nodes:
<%
  require 'json'
  nodes = JSON.parse(ENV.fetch('TARGET_NODES', '[]'))
  nodes.each do |n|
%>
    - name: <%= n['name'] %>
      test-kitchen-mode: real
      endpoint: <%= n['endpoint'] %>
      credential-map-file: test/credentials.yml
      credential-passing-mode: pass-by-creds-file
<% end %>
```

Set `TARGET_NODES` before running kitchen:

```bash
export TARGET_NODES='[{"name":"web01","endpoint":"10.0.0.1:22"},{"name":"web02","endpoint":"10.0.0.2:22"}]'
kitchen converge
```

### Targets from a file

```yaml
agentless:
  remote_nodes:
<%
  require 'yaml'
  nodes = YAML.safe_load(File.read('test/target-nodes.yml'))
  nodes.each do |n|
%>
    - name: <%= n['name'] %>
      test-kitchen-mode: real
      endpoint: <%= n['endpoint'] %>
      credential-map-file: test/credentials.yml
      credential-passing-mode: pass-by-creds-file
<% end %>
```

The `ErbNodeListHelper` module (from `kitchen-chef-infra-agentless`) provides convenience helpers:

```yaml
<%
  require 'kitchen/agentless/erb_node_list_helper'
  include Kitchen::Agentless::ErbNodeListHelper
%>
agentless:
  remote_nodes:
    <%= nodes_from_env('TARGET_NODES') %>
```

---

## Secret Masking

TKE wraps the kitchen logger in a `SecretMasker` proxy that redacts credential values before they appear in any log output. The masking is applied automatically during `kitchen converge` — no configuration is required.

Masked values appear as `[MASKED]` in logs:

```
       Connecting to winhost01 via winrm://Administrator@10.0.0.10:5985
       Using credential: [MASKED]
```

---

## Incompatible Resource Detection

Before each converge, TKE scans the run list for resources known to be incompatible with Agentless / Target Mode. If incompatible resources are found, a clear `UserError` is raised:

```
ERROR: The following resources in your run list are not supported in
Agentless Mode (chef-client --target):
  - service[nginx] — service management requires systemd on the target
  - package[curl] — package installation requires root on the target node
Please remove or guard these resources with node['target_mode'] before
running in agentless mode.
```

---

## Project Structure

A typical cookbook project using Agentless Mode:

```
my-cookbook/
├── kitchen.yml              # Agentless kitchen configuration
├── test/
│   ├── credentials.yml      # Credential mappings (gitignored in production)
│   ├── data/                # Data bags, environments, roles
│   └── target-nodes.yml     # Optional: dynamic node list for CI
├── recipes/
│   └── default.rb
└── spec/
```

> Add `test/credentials.yml` to `.gitignore` if it contains plaintext credentials.

---

## Full Example

```yaml
# kitchen.yml
---
driver:
  name: dokken
  chef_image: chef/chef

transport:
  name: dokken

provisioner:
  name: chef-infra-agentless
  data_path: test/data
  agentless:
    parallel-mode: disabled
    remote_nodes:
      - name: edge-device-1
        test-kitchen-mode: container
        test-kitchen-image: dokken/ubuntu-24.04
        credential-map-file: test/credentials.yml
        credential-passing-mode: pass-by-creds-file
      - name: edge-device-2
        test-kitchen-mode: real
        endpoint: 192.168.100.5:22
        credential-map-file: test/credentials.yml
        credential-passing-mode: pass-cmd-line

verifier:
  name: inspec

platforms:
  - name: ubuntu-24.04

suites:
  - name: default
    run_list:
      - recipe[my_cookbook::default]
      - recipe[my_cookbook::hardening]
```

```yaml
# test/credentials.yml
remote-nodes:
  - name: edge-device-1
    credential-source-type: credential-file
    transport: ssh
    credential-source: test/chef-creds.toml

  - name: edge-device-2
    credential-source-type: inline
    transport: ssh
    ssh-user: admin
    ssh-pass: "changeme"    # ⚠️  triggers OWASP plaintext warning
```

---

## Limitations

- Requires Dokken driver (source container must run Chef 18+)
- `kitchen verify` with InSpec against remote nodes is a future epic
- Mixed agent-based and agentless runs in the same `kitchen.yml` are not supported
- Chef 360 Secret Service, Hashi Vault, and environment-variable credential passing are out of scope for this release

---

## See Also

- [Dokken Driver](../drivers/dokken)
- [SSH Transport](../transports/ssh)
- [WinRM Transport](../transports/winrm)
- [Chef Infra Provisioner](../provisioners/chef)
- [Chef Infra Target Mode documentation](https://docs.chef.io/target_mode/)
