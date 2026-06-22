# Agentless Mode Architecture: Wave 14 Redesign

> **Document scope:** Explains the complete architecture evolution of Agentless Mode
> for Test Kitchen Enterprise — from the original Wave 1–13 design through the
> Wave 14 redesign, including the motivations, problems solved, and how every
> component changed.
>
> **Related repos:**
> - `chef/chef-test-kitchen-enterprise` (TKE) — core framework (this repo)
> - `chef/kitchen-chef-infra-agentless` (KCAI) — agentless provisioner plugin

---

## Table of Contents

1. [What Is Agentless Mode?](#1-what-is-agentless-mode)
2. [Previous Architecture (Waves 1–13)](#2-previous-architecture-waves-113)
   - 2.1 [Overview](#21-overview)
   - 2.2 [Component Diagram](#22-component-diagram)
   - 2.3 [Instance Lifecycle Flow](#23-instance-lifecycle-flow)
   - 2.4 [kitchen.yml Format](#24-kitchenyml-format)
   - 2.5 [Assignment Strategies](#25-assignment-strategies)
3. [Problems With the Previous Architecture](#3-problems-with-the-previous-architecture)
   - 3.1 [TK Lifecycle Violation](#31-tk-lifecycle-violation)
   - 3.2 [Dual-Role Confusion](#32-dual-role-confusion)
   - 3.3 [Assignment Complexity](#33-assignment-complexity)
   - 3.4 [Parallel Mode Overhead](#34-parallel-mode-overhead)
4. [New Architecture (Wave 14)](#4-new-architecture-wave-14)
   - 4.1 [Core Principle](#41-core-principle)
   - 4.2 [Component Diagram](#42-component-diagram)
   - 4.3 [Instance Lifecycle Flow](#43-instance-lifecycle-flow)
   - 4.4 [kitchen.yml Format](#44-kitchenyml-format)
   - 4.5 [Source Node Modes](#45-source-node-modes)
5. [Side-by-Side Comparison](#5-side-by-side-comparison)
6. [Component Reference](#6-component-reference)
   - 6.1 [Removed Components](#61-removed-components)
   - 6.2 [New Components](#62-new-components)
   - 6.3 [Modified Components](#63-modified-components)
7. [Migration Guide](#7-migration-guide)
8. [Sequence Diagrams](#8-sequence-diagrams)
   - 8.1 [Old: kitchen create](#81-old-kitchen-create)
   - 8.2 [New: kitchen create](#82-new-kitchen-create)
   - 8.3 [Old: kitchen converge](#83-old-kitchen-converge)
   - 8.4 [New: kitchen converge](#84-new-kitchen-converge)

---

## 1. What Is Agentless Mode?

Chef Infra's **Target Mode** (`chef-client --target <host>`) allows a Chef
Infra Client to manage a remote node over SSH or WinRM **without** installing
chef-client on the target.  A "source" machine runs the client; the "target"
machine only needs SSH/WinRM access.

**Agentless Mode** is the Test Kitchen integration for Target Mode.  It allows
`kitchen converge` to apply a cookbook to a remote node without any Chef
installation on that node — essential for network appliances, IoT devices,
legacy systems, or any host where installing Chef Infra Client is impossible or
undesired.

---

## 2. Previous Architecture (Waves 1–13)

### 2.1 Overview

In the original design (Waves 1–13), the **Kitchen instance was the SOURCE node**
— the machine that ran `chef-client --target`.  Remote (target) nodes were a
separate, optional list configured inside the `agentless:` block under the
provisioner.

```
Kitchen Instance  =  SOURCE  (where chef runs)
agentless.remote_nodes  =  TARGETS  (what chef manages)
```

A single Kitchen instance could be assigned multiple remote target nodes via
two assignment strategies:

| Strategy | Config format | Behaviour |
|---|---|---|
| Pool | `remote_nodes: [...]` (Array) | Nodes assigned round-robin across instances |
| Explicit | `remote_nodes: {...}` (Hash) | Nodes keyed by instance name |

Within a single instance, multiple targets could be run in **parallel** via
`parallel-mode: enabled`.

### 2.2 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       kitchen.yml (Waves 1–13)                          │
│                                                                         │
│  driver:                                                                │
│    name: dokken             ← Creates SOURCE container                  │
│                                                                         │
│  provisioner:                                                           │
│    name: chef-infra-agentless                                           │
│    agentless:                                                           │
│      parallel-mode: disabled                                            │
│      remote_nodes:          ← TARGETS configured here                   │
│        - name: node1                                                    │
│          test-kitchen-mode: container                                   │
│        - name: node2                                                    │
│          test-kitchen-mode: real                                        │
│          endpoint: 10.0.0.5:22                                          │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                    Runtime Topology (Waves 1–13)                        │
│                                                                         │
│  ┌──────────────────────────────────┐                                   │
│  │  Kitchen Instance (SOURCE)       │                                   │
│  │  ┌─────────────────────────┐     │                                   │
│  │  │  Driver: Dokken/EC2     │     │  kitchen create                   │
│  │  │  (creates source VM)    │     │  ─────────────────►               │
│  │  └─────────────────────────┘     │                                   │
│  │  ┌─────────────────────────┐     │                                   │
│  │  │  Transport: SSH/Dokken  │◄────┼─── TKE connects HERE              │
│  │  └─────────────────────────┘     │                                   │
│  │  ┌─────────────────────────┐     │                                   │
│  │  │  Provisioner:           │     │                                   │
│  │  │  ChefInfraAgentless     │     │                                   │
│  │  │  ┌───────────────────┐  │     │                                   │
│  │  │  │ AgentlessContext  │  │     │                                   │
│  │  │  │ - parallel_mode   │  │     │                                   │
│  │  │  │ - TargetAssignment│  │     │                                   │
│  │  │  │   Pool | Explicit │  │     │                                   │
│  │  │  └───────────────────┘  │     │                                   │
│  │  └─────────────────────────┘     │                                   │
│  └──────────────────────────────────┘                                   │
│                │                                                        │
│                │  chef-client --target <uri>                            │
│                │                                                        │
│         ┌──────┴──────────────────────────┐                             │
│         ▼                                 ▼                             │
│  ┌─────────────┐                  ┌─────────────┐                       │
│  │  TARGET 1   │                  │  TARGET 2   │                       │
│  │  (container │                  │  (real node │                       │
│  │   or real)  │                  │   or EC2)   │                       │
│  └─────────────┘                  └─────────────┘                       │
│                                                                         │
│  Remote nodes are SEPARATE from Kitchen instances.                      │
│  Assignment: Pool (round-robin) OR Explicit (by instance name).         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Instance Lifecycle Flow

```
kitchen create
  └─► Driver creates SOURCE container/VM
  └─► provisioner.after_create(state)
        ├─► Container targets: start Docker container, record endpoint
        ├─► Driver targets: call RemoteNodeDriverAdapter.create → spin up EC2/Vagrant
        └─► Real targets: log "skipping (real node)"

kitchen setup
  └─► provisioner.after_setup(state)
        └─► Upload credentials to SOURCE via instance.transport

kitchen converge
  └─► provisioner.call(state)
        ├─► preflight_credential_check
        ├─► bootstrap_chef_on_source (install chef on SOURCE)
        ├─► [parallel?] ParallelRunner.run_all(tasks)
        │     └─► Thread per target: chef-client --target <uri>
        └─► [sequential] call_sequential(state)
              └─► For each target:
                    ├─► CredentialProvisioner.provision (SOURCE transport)
                    ├─► AgentlessRunner.converge
                    │     └─► Upload sandbox → SOURCE via instance.transport
                    │     └─► conn.execute("chef-client --target ...")
                    └─► CredentialProvisioner.cleanup

kitchen destroy
  └─► provisioner.before_destroy(state)
        ├─► Remove credentials from SOURCE
        ├─► Container targets: stop Docker container
        ├─► Driver targets: RemoteNodeDriverAdapter.destroy
        └─► Real targets: log "skipping"
  └─► Driver destroys SOURCE container/VM
```

### 2.4 kitchen.yml Format

```yaml
# Waves 1-13 format
driver:
  name: dokken
  chef_image: chef/chef:latest   # SOURCE image

provisioner:
  name: chef-infra-agentless
  agentless:
    parallel-mode: disabled        # enabled | disabled | auto
    remote_nodes:
      # POOL MODE (Array) — round-robin across instances
      - name: target1
        test-kitchen-mode: container
        test-kitchen-image: dokken/ubuntu-24.04
        credential-map-file: test/credentials.yml
        credential-passing-mode: pass-by-creds-file

      # EXPLICIT MODE (Hash) — keyed by instance name
      default-ubuntu-2404:
        test-kitchen-mode: real
        endpoint: "10.0.0.10:22"
        credential-map-file: test/credentials.yml
        credential-passing-mode: pass-cmd-line
```

### 2.5 Assignment Strategies

#### Pool Mode (Array)

```
remote_nodes: [nodeA, nodeB, nodeC]

instance-0  →  nodeA  (index 0 % 3)
instance-1  →  nodeB  (index 1 % 3)
instance-2  →  nodeC  (index 2 % 3)
instance-3  →  nodeA  (index 3 % 3)   ← pool wraps around
```

Pool index was computed via:
1. Sort all instance names alphabetically → find position
2. Fallback: parse `kitchen.yml` suite×platform matrix
3. Last resort: byte-sum of instance name (collision-prone, warned)

#### Explicit Mode (Hash)

```yaml
remote_nodes:
  default-ubuntu-2404:             # single node
    test-kitchen-mode: real
    endpoint: "10.0.0.10:22"
  default-almalinux-9:             # multiple nodes (Array value)
    - test-kitchen-mode: real
      endpoint: "10.0.0.11:22"
    - test-kitchen-mode: real
      endpoint: "10.0.0.12:22"
```

---

## 3. Problems With the Previous Architecture

### 3.1 TK Lifecycle Violation

**The most fundamental problem:** Test Kitchen's entire design is built around
the lifecycle of a single _instance_ — an (instance name) = (suite) × (platform)
combination.  Each TK command (`create`, `converge`, `destroy`) operates on
instances.  Drivers, transports, provisioners, and verifiers all map to one
instance.

In Waves 1–13:

```
Kitchen Instance  →  SOURCE  (the machine running chef-client)
Remote nodes      →  TARGETS (what you actually want to test)
```

This inverted the natural TK mental model.  When a user ran:

```
kitchen converge default-ubuntu-2404
```

They expected it to converge the `default-ubuntu-2404` node.  Instead, it
converged whatever target node happened to be **assigned** to the
`default-ubuntu-2404` _source_ instance — which was a completely different
machine.  This caused constant confusion:

- `kitchen list` showed source VM status, not target node status
- `kitchen destroy` destroyed the source VM, NOT the target
- Driver config (AMI, instance type) applied to the SOURCE, but users assumed it applied to the target
- InSpec verifier ran against the SOURCE, not the target it was supposed to test

### 3.2 Dual-Role Confusion

The `remote_nodes` list was disconnected from Kitchen instances.  A remote
node could be a Docker container (started by the provisioner, not the driver),
a real pre-existing machine, or a driver-managed VM — but none of these were
first-class Kitchen instances.  They had no proper lifecycle tracking in the
TK instance table.

This led to a parallel, shadow lifecycle inside the provisioner that duplicated
what TK's driver system already does:

| TK driver lifecycle | Provisioner shadow lifecycle |
|---|---|
| `driver.create(state)` | `RemoteNodeDriverAdapter.create` |
| `driver.destroy(state)` | `RemoteNodeDriverAdapter.destroy` |
| `instance.transport` | Custom container SSH readiness check |
| `kitchen.yml driver:` | `remote_nodes[n].driver:` nested block |

### 3.3 Assignment Complexity

The pool/explicit assignment system added significant complexity:

- **Pool mode** required computing a stable index across instances — three
  different fallback strategies (instance list, YAML parse, byte-sum hash) just
  to figure out which node mapped to which instance.
- **Explicit mode** allowed multiple nodes per instance (Array values), requiring
  a flat-map and per-index node IDs (`"instance-name[0]"`, `"instance-name[1]"`).
- Pool nodes could be shared between instances (the "(shared with …)" annotation
  in `kitchen list`).
- Unused pool nodes appeared in a separate `Unused Pool Nodes` section.
- None of this complexity was necessary if each instance simply _was_ a target node.

### 3.4 Parallel Mode Overhead

`parallel-mode: enabled` ran multiple target converges in Ruby threads within
a single Kitchen instance.  This was a custom threading layer on top of what
TK already provides natively:

```bash
# TK native parallelism — no parallel-mode needed
kitchen converge -c 4    # converge 4 instances in parallel
```

Maintaining a custom `ParallelRunner` class with thread-based coordination,
thread-safe logging, and per-thread error collection duplicated TK's own
`-c N` concurrency mechanism without providing any benefit.

---

## 4. New Architecture (Wave 14)

### 4.1 Core Principle

> **Each Kitchen instance IS the remote (target) node.**

```
Kitchen Instance  =  TARGET  (what chef-client manages)
agentless.source  =  SOURCE  (where chef-client runs)
```

The driver creates the **target** VM.  The transport connects to the **target**.
The source is configured separately via the new `agentless.source:` block — it
is either the developer's local machine or a separate source VM that the
provisioner manages alongside the instance.

This aligns perfectly with TK's existing mental model:
- `kitchen create default-ubuntu-2404` → creates the `default-ubuntu-2404` **target**
- `kitchen converge default-ubuntu-2404` → runs chef-client targeting `default-ubuntu-2404`
- `kitchen destroy default-ubuntu-2404` → destroys the `default-ubuntu-2404` **target**

### 4.2 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       kitchen.yml (Wave 14+)                            │
│                                                                         │
│  driver:                                                                │
│    name: ec2                ← Creates TARGET VM                         │
│    image_id: ami-TARGET                                                 │
│                                                                         │
│  provisioner:                                                           │
│    name: chef-infra-agentless                                           │
│    agentless:                                                           │
│      source:                ← SOURCE configured here                    │
│        mode: local          ← (or vm)                                   │
│      remote_nodes:          ← 1:1 map by instance name                  │
│        default-ubuntu-2404:                                             │
│          test-kitchen-mode: driver                                      │
│          transport:                                                     │
│            ssh_key: ~/.ssh/target.pem                                   │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                    Runtime Topology (Wave 14)                           │
│                                                                         │
│  ┌──────────────────────────────────┐                                   │
│  │  Kitchen Instance (TARGET)       │                                   │
│  │  ┌─────────────────────────┐     │                                   │
│  │  │  Driver: EC2/Dokken     │     │  kitchen create                   │
│  │  │  (creates TARGET VM)    │     │  ─────────────────►               │
│  │  └─────────────────────────┘     │                                   │
│  │  ┌─────────────────────────┐     │                                   │
│  │  │  Transport: SSH         │◄────┼─── TKE connects HERE              │
│  │  │  (to TARGET)            │     │    (for setup/verify)             │
│  │  └─────────────────────────┘     │                                   │
│  │  ┌─────────────────────────┐     │                                   │
│  │  │  Provisioner:           │     │                                   │
│  │  │  ChefInfraAgentless     │     │                                   │
│  │  │  ┌───────────────────┐  │     │                                   │
│  │  │  │ AgentlessContext  │  │     │                                   │
│  │  │  │ - source_config   │  │     │                                   │
│  │  │  │ - remote_nodes{}  │  │     │                                   │
│  │  │  └───────────────────┘  │     │                                   │
│  │  └─────────────────────────┘     │                                   │
│  └──────────────────────────────────┘                                   │
│                                                                         │
│  ┌──────────────────────────────────┐                                   │
│  │  SOURCE NODE                     │                                   │
│  │                                  │                                   │
│  │  mode: local                     │                                   │
│  │  ┌─────────────────────────┐     │                                   │
│  │  │  LocalSourceTransport   │     │  Commands run via                 │
│  │  │  (Mixlib::ShellOut)     │     │  Mixlib::ShellOut on              │
│  │  └─────────────────────────┘     │  developer's machine              │
│  │                                  │                                   │
│  │  mode: vm                        │                                   │
│  │  ┌─────────────────────────┐     │                                   │
│  │  │  SourceNodeDriverAdapter│     │  Separate VM created              │
│  │  │  (same driver, diff AMI)│     │  by provisioner via               │
│  │  └─────────────────────────┘     │  driver class directly            │
│  └──────────────────────────────────┘                                   │
│                                                                         │
│                │                                                        │
│                │  chef-client --target <TARGET_URI>                     │
│                ▼                                                        │
│  ┌──────────────────────────────────┐                                   │
│  │  TARGET NODE (= Kitchen Instance)│                                   │
│  │  No chef-client installed        │                                   │
│  │  Managed via SSH/WinRM           │                                   │
│  └──────────────────────────────────┘                                   │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.3 Instance Lifecycle Flow

```
kitchen create
  └─► Driver creates TARGET VM (standard TK lifecycle)
  └─► provisioner.after_create(state)
        ├─► [container target] Start Docker container, record endpoint
        ├─► [driver target]    Record endpoint from state[:hostname] (driver already created it)
        ├─► [real target]      Log "skipping create (real node)"
        └─► [source.mode: vm]  SourceNodeDriverAdapter.create → spin up SOURCE VM
                               Record source VM state in agentless state file

kitchen setup
  └─► provisioner.after_setup(state)
        └─► Upload credentials to SOURCE via source_transport(state)
              (LocalSourceTransport for local mode, SSH for vm mode)

kitchen converge
  └─► provisioner.call(state)
        ├─► remote_node_for_instance → look up node by instance.name
        ├─► [no node] warn + fall back to standard ChefInfra.call
        ├─► preflight_credential_check([node])
        ├─► bootstrap_chef_on_source (only for non-local, non-Dokken sources)
        └─► call_agentless(state, node)
              ├─► source_transport(state)  ← local or SSH to source VM
              ├─► CredentialProvisioner.prepare_credentials (truncate stale entries)
              ├─► CredentialProvisioner.provision (upload to SOURCE)
              ├─► AgentlessRunner.converge(source_transport: st)
              │     ├─► Upload sandbox to SOURCE
              │     └─► conn.execute("chef-client --target <TARGET_URI> ...")
              └─► CredentialProvisioner.cleanup

kitchen destroy
  └─► provisioner.before_destroy(state)
        ├─► Remove credentials from SOURCE via source_transport(state)
        ├─► [container target]  Stop Docker container
        ├─► [real target]       Log "skipping"
        ├─► [driver target]     Driver handles it (it IS the instance)
        └─► [source.mode: vm]   SourceNodeDriverAdapter.destroy → terminate SOURCE VM
  └─► Driver destroys TARGET VM (standard TK lifecycle)
```

### 4.4 kitchen.yml Format

```yaml
# Wave 14 format

# The driver creates the TARGET VM.
driver:
  name: ec2
  image_id: ami-0abc123target
  instance_type: t3.medium
  region: us-east-1
  subnet_id: subnet-abc123
  security_group_ids: [sg-abc123]

# The transport connects TK to the TARGET VM.
transport:
  name: ssh
  username: ubuntu
  ssh_key: ~/.ssh/target.pem

provisioner:
  name: chef-infra-agentless
  run_list:
    - recipe[my_cookbook::default]

  agentless:
    # SOURCE: where chef-client runs
    source:
      mode: local    # local = developer's machine (default)
                     # vm    = separate VM created by the driver

      # vm mode only: override driver config for the source VM
      driver_overrides:
        image_id: ami-0def456source   # different AMI for source
        instance_type: t3.small       # source can be smaller

      # vm mode only: how to SSH into the source VM
      transport:
        username: ubuntu
        ssh_key: ~/.ssh/source.pem

    # TARGETS: 1:1 mapping, key = Kitchen instance name
    remote_nodes:
      default-ubuntu-2404:
        test-kitchen-mode: driver    # driver = TK instance IS the target
        transport:
          username: ubuntu
          ssh_key: ~/.ssh/target.pem

suites:
  - name: default

platforms:
  - name: ubuntu-2404

# Results in one instance: default-ubuntu-2404
# That instance IS the target node.
```

#### Modes for `test-kitchen-mode`

| Mode | Who creates the target? | When to use |
|---|---|---|
| `driver` | TK driver (standard `kitchen create`) | EC2, Vagrant, Azure, Proxy — any SSH-based driver |
| `real` | Pre-existing machine — TK does nothing | Network appliances, production servers, manually provisioned VMs |
| `container` | `ContainerNodeManager` (Docker) | Dokken-style container targets (note: source must also be local or Dokken) |

### 4.5 Source Node Modes

#### `mode: local` (default)

Chef-client runs on the developer's local machine.  No VM is created.
Commands are executed via `Mixlib::ShellOut`.  File uploads use `FileUtils.cp_r`.

```
Developer Machine
  ├── kitchen (Ruby process)
  ├── chef-client (installed locally)
  └── LocalSourceTransport
        └── Mixlib::ShellOut.new("chef-client --target ssh://...")
```

Requirements:
- `chef-client` must be installed on the local machine
- Local machine must have network access to the target

#### `mode: vm`

A separate source VM is created using the same driver class that manages the
target, but with different driver config overrides (e.g., a different AMI or
instance type).

```
EC2 Region
  ├── Target VM (created by kitchen create)     ← Kitchen Instance
  └── Source VM (created by provisioner)        ← managed by SourceNodeDriverAdapter
        └── chef-client installed during converge
        └── SSH transport (SourceVmTransportWrapper)
```

The source VM state is persisted in the agentless state file
(`.kitchen/<instance>-agentless.yml`) under the `source_node:` key and cleaned
up during `kitchen destroy`.

---

## 5. Side-by-Side Comparison

```
┌────────────────────────────┬──────────────────────────────────┬───────────────────────────────────────┐
│ Aspect                     │ Waves 1–13                       │ Wave 14                               │
├────────────────────────────┼──────────────────────────────────┼───────────────────────────────────────┤
│ Kitchen Instance role       │ SOURCE (chef runs here)          │ TARGET (chef targets this)           │
│ Driver creates              │ Source VM/container              │ Target VM/container                  │
│ instance.transport          │ Connects to SOURCE               │ Connects to TARGET                   │
│ remote_nodes format         │ Array (pool) OR Hash (explicit)  │ Hash only, keyed by instance name    │
│ Nodes per instance          │ One or more (explicit multi-node)│ Exactly one                          │
│ Assignment strategy         │ Pool (round-robin) or explicit   │ None — direct lookup by name         │
│ Parallel targets            │ ParallelRunner (threads)         │ TK native: kitchen converge -c N     │
│ Source configuration        │ Implicit (= instance)            │ Explicit agentless.source: block     │
│ Source transport            │ instance.transport               │ source_transport(state)              │
│ Source mode options         │ Dokken container only            │ local or vm                          │
│ Pool overflow display       │ "Unused Pool Nodes" section      │ Removed                              │
│ Pool sharing annotation     │ "(shared with <instance>)"       │ Removed                              │
│ kitchen list shows          │ Source VM status                 │ Target node status (correct)         │
│ kitchen destroy destroys    │ Source VM                        │ Target VM (correct)                  │
│ InSpec verifier runs on     │ Source (wrong)                   │ Target (correct — future epic)       │
│ RemoteNodeDriverAdapter     │ Creates target VMs               │ Replaced by SourceNodeDriverAdapter  │
│ AgentlessRunner transport   │ @instance.transport (hardcoded)  │ source_transport kwarg (flexible)    │
│ Assignment complexity       │ 3-fallback stable index, node_id │ Simple Hash lookup by name           │
│ Classes deleted             │ -                                │ Pool, Explicit, ParallelRunner       │
│ Classes added               │ -                                │ SourceConfig, LocalSourceTransport   │
│                             │                                  │ SourceNodeDriverAdapter              │
└─────────────────────────────┴──────────────────────────────────┴──────────────────────────────────────┘
```

---

## 6. Component Reference

### 6.1 Removed Components

These classes were **deleted** in Wave 14:

| File | Class | Why removed |
|---|---|---|
| `lib/kitchen/target_assignment/pool.rb` | `Kitchen::TargetAssignment::Pool` | Pool mode removed; TK `-c N` handles parallelism |
| `lib/kitchen/target_assignment/explicit.rb` | `Kitchen::TargetAssignment::Explicit` | Assignment logic replaced by simple Hash lookup |
| `lib/kitchen/agentless/parallel_runner.rb` | `Kitchen::Agentless::ParallelRunner` | Parallel mode removed |
| `spec/kitchen/target_assignment/pool_spec.rb` | — | Test for deleted class |
| `spec/kitchen/target_assignment/explicit_spec.rb` | — | Test for deleted class |
| `spec/kitchen/agentless/parallel_runner_spec.rb` | — | Test for deleted class |

These **methods/features** were removed from surviving classes:

| Class | Removed method/feature | Replacement |
|---|---|---|
| `Context` | `pool_mode?`, `explicit_mode?`, `assignment_form`, `parallel_mode` | None — not needed |
| `Context` | Array `remote_nodes` (pool form) | Raises `UserError` with migration message |
| `RemoteNode` | `assignment_key` attribute | Not needed in 1:1 model |
| `ChefInfraAgentless` | `target_assignment`, `node_for`, `all_pool_nodes` | `remote_node_for_instance` |
| `ChefInfraAgentless` | `render_pool_overflow_section` | Removed |
| `ChefInfraAgentless` | `call_sequential`, `call_parallel` | `call_agentless` |
| `ChefInfraAgentless` | `resolve_assigned_nodes`, `instance_nodes` | `remote_node_for_instance` |
| `ChefInfraAgentless` | `parallel_mode_enabled?`, `warn_on_pool_*` | Removed |
| `ChefInfraAgentless` | `stable_pool_index` and 3 helpers | Removed |
| `List` (TKE) | `list_unused_pool_nodes` | Removed |
| `List` (TKE) | `first_seen_map` building | Removed |

### 6.2 New Components

| File | Class | Purpose |
|---|---|---|
| `lib/kitchen/agentless/source_config.rb` | `Kitchen::Agentless::SourceConfig` | Parses `agentless.source:` block; validates `mode: local\|vm` |
| `lib/kitchen/agentless/local_source_transport.rb` | `Kitchen::Agentless::LocalSourceTransport` | Executes commands on local machine via `Mixlib::ShellOut`; uploads via `FileUtils.cp_r` |
| `lib/kitchen/agentless/source_node_driver_adapter.rb` | `Kitchen::Agentless::SourceNodeDriverAdapter` | Creates/destroys source VM using same driver class with overrides |
| `spec/kitchen/agentless/source_config_spec.rb` | — | Tests for SourceConfig |
| `spec/kitchen/agentless/local_source_transport_spec.rb` | — | Tests for LocalSourceTransport |

**New inner class:**

| Class | Location | Purpose |
|---|---|---|
| `ChefInfraAgentless::SourceVmTransportWrapper` | `chef_infra_agentless.rb` | Wraps SSH transport to fix source VM state; routes `connection(_state)` calls to source VM |

### 6.3 Modified Components

#### `Kitchen::Agentless::Context`

```ruby
# Old API
ctx.parallel_mode          # "disabled" | "enabled" | "auto"
ctx.assignment_form        # :pool | :explicit
ctx.pool_mode?             # bool
ctx.explicit_mode?         # bool
ctx.remote_nodes           # Array<RemoteNode>

# New API
ctx.source_config          # Kitchen::Agentless::SourceConfig
ctx.remote_nodes           # Hash{ String => RemoteNode }  (instance_name => node)
ctx.node_for("inst-name")  # RemoteNode | nil
```

#### `Kitchen::Agentless::RemoteNode`

```ruby
# Removed attribute:
node.assignment_key   # REMOVED — not needed in 1:1 model

# Unchanged attributes:
node.name, node.node_id, node.mode, node.endpoint,
node.credential_map_file, node.credential_passing_mode,
node.transport, node.remote_transport_config, ...
```

#### `Kitchen::Provisioner::ChefInfraAgentless`

```ruby
# Old public API
provisioner.node_for(instance_name, instance_index)     # REMOVED
provisioner.target_assignment                            # REMOVED
provisioner.all_pool_nodes                               # REMOVED
provisioner.render_pool_overflow_section(shell, names)  # REMOVED
provisioner.render_list_section(shell, name, map)       # 3 args

# New public API
provisioner.remote_node_for_instance    # RemoteNode | nil
provisioner.render_list_section(shell, name)  # 2 args (no map needed)
```

#### `Kitchen::Agentless::AgentlessRunner`

```ruby
# Old constructor
AgentlessRunner.new(instance, config, logger)

# New constructor  — source_transport is injectable
AgentlessRunner.new(instance, config, logger, source_transport: st)
# Default: source_transport = instance.transport (backward compat)
```

All internal uses of `@instance.transport` replaced with `@source_transport`.

---

## 7. Migration Guide

### Updating `kitchen.yml`

**Before (Waves 1–13):**

```yaml
driver:
  name: dokken
  chef_image: chef/chef:latest

provisioner:
  name: chef-infra-agentless
  agentless:
    parallel-mode: disabled
    remote_nodes:
      # Pool mode (Array)
      - name: my-target
        test-kitchen-mode: real
        endpoint: "10.0.0.5:22"
        credential-map-file: test/credentials.yml
        credential-passing-mode: pass-cmd-line

suites:
  - name: default
platforms:
  - name: ubuntu-2404
```

**After (Wave 14+):**

```yaml
driver:
  name: proxy          # or ec2, vagrant, etc.
  host: 10.0.0.5
  port: 22

transport:
  name: ssh
  username: ubuntu
  ssh_key: ~/.ssh/id_rsa

provisioner:
  name: chef-infra-agentless
  agentless:
    source:
      mode: local      # chef-client runs on your machine
    remote_nodes:
      default-ubuntu-2404:          # ← must match the instance name exactly
        test-kitchen-mode: real
        endpoint: "10.0.0.5:22"    # still used for the --target URI
        credential-map-file: test/credentials.yml
        credential-passing-mode: pass-cmd-line

suites:
  - name: default
platforms:
  - name: ubuntu-2404
```

### Key Migration Rules

1. **`remote_nodes` must be a Hash** — if you have an Array (pool mode), each
   entry must become a Hash key matching its Kitchen instance name.

2. **One entry per instance** — remove multi-node Array values under a single
   key.  If you needed multiple targets per run, use multiple suites/platforms
   and multiple `kitchen converge -c N` jobs.

3. **Remove `parallel-mode`** — delete this key entirely.  Use
   `kitchen converge -c N` for parallel execution across instances.

4. **The driver now creates the TARGET** — update your driver config (AMI,
   image, box) to point to the target image, not a source image.

5. **Add `agentless.source:`** — configure how chef-client reaches targets:
   - `mode: local` (default): chef-client already installed on your machine
   - `mode: vm`: driver creates a source VM

6. **Array remote_nodes raises `UserError`** — the provisioner immediately
   errors with a clear migration message if an Array is detected.

---

## 8. Sequence Diagrams

### 8.1 Old: `kitchen create`

```
User          TK Core          Driver           Provisioner           Docker/EC2
  │                │                │                  │                    │
  │ kitchen create │                │                  │                    │
  │───────────────►│                │                  │                    │
  │                │ driver.create  │                  │                    │
  │                │───────────────►│                  │                    │
  │                │                │  create SOURCE   │                    │
  │                │                │  VM/container    │                    │
  │                │                │──────────────────────────────────────►│
  │                │                │◄──────────────────────────────────────│
  │                │                │  state[:hostname]│                    │
  │                │◄───────────────│                  │                    │
  │                │                                   │                    │
  │                │ provisioner.after_create(state)   │                    │
  │                │──────────────────────────────────►│                    │
  │                │                                   │ start TARGET       │
  │                │                                   │ containers/VMs     │
  │                │                                   │ (for each node)    │
  │                │                                   │───────────────────►│
  │                │                                   │◄───────────────────│
  │                │◄──────────────────────────────────│                    │
  │◄───────────────│                                   │                    │
```

### 8.2 New: `kitchen create`

```
User          TK Core          Driver           Provisioner           Docker/EC2
  │                │                │                  │                    │
  │ kitchen create │                │                  │                    │
  │───────────────►│                │                  │                    │
  │                │ driver.create  │                  │                    │
  │                │───────────────►│                  │                    │
  │                │                │  create TARGET   │                    │
  │                │                │  VM/container    │                    │
  │                │                │──────────────────────────────────────►│
  │                │                │◄──────────────────────────────────────│
  │                │◄───────────────│  state[:hostname]│                    │
  │                │                                   │                    │
  │                │ provisioner.after_create(state)   │                    │
  │                │──────────────────────────────────►│                    │
  │                │                                   │ record target      │
  │                │                                   │ endpoint in        │
  │                │                                   │ agentless state    │
  │                │                                   │                    │
  │                │                    [source.mode:vm only]               │
  │                │                                   │ SourceNodeDriver   │
  │                │                                   │ Adapter.create     │
  │                │                                   │───────────────────►│
  │                │                                   │◄───────────────────│
  │                │◄──────────────────────────────────│  source created    │
  │◄───────────────│                                   │                    │
```

### 8.3 Old: `kitchen converge`

```
User       TK Core      SourceTransport    Provisioner    TargetNode
  │              │              │                │               │
  │ converge     │              │                │               │
  │─────────────►│              │                │               │
  │              │ call(state)  │                │               │
  │              │─────────────────────────────► │               │
  │              │              │                │               │
  │              │              │  preflight     │               │
  │              │              │  bootstrap     │               │
  │              │              │  create_sandbox│               │
  │              │              │                │               │
  │              │              │  provision     │               │
  │              │              │  credentials   │               │
  │              │◄─────────────│                │               │
  │              │ transport    │                │               │
  │              │ .connection  │                │               │
  │              │─────────────►│                │               │
  │              │              │ upload sandbox │               │
  │              │              │ to SOURCE      │               │
  │              │              │ execute:       │               │
  │              │              │ chef-client    │               │
  │              │              │ --target       │──────────────►│
  │              │              │                │  SSH/WinRM    │
  │              │              │◄───────────────│───────────────│
  │◄─────────────│              │                │               │
```

### 8.4 New: `kitchen converge`

```
User       TK Core     SourceTransport    Provisioner    TargetNode
  │              │             │                │               │
  │ converge     │             │                │               │
  │─────────────►│             │                │               │
  │              │ call(state) │                │               │
  │              │────────────────────────────► │               │
  │              │             │                │               │
  │              │             │  remote_node_  │               │
  │              │             │  for_instance  │               │
  │              │             │  [lookup by    │               │
  │              │             │  instance.name]│               │
  │              │             │                │               │
  │              │             │  preflight     │               │
  │              │             │  source_       │               │
  │              │             │  transport()   │               │
  │              │             │  [local or SSH │               │
  │              │             │   to source VM]│               │
  │              │             │                │               │
  │              │             │  provision     │               │
  │              │             │  credentials   │               │
  │              │             │  on SOURCE     │               │
  │              │             │                │               │
  │              │  source_transport.connection │               │
  │              │────────────►│                │               │
  │              │             │ upload sandbox │               │
  │              │             │ to SOURCE      │               │
  │              │             │ execute:       │               │
  │              │             │ chef-client    │               │
  │              │             │ --target       │──────────────►│
  │              │             │                │  SSH/WinRM    │
  │              │             │◄───────────────│───────────────│
  │◄─────────────│             │                │               │
```

---

## Summary

The Wave 14 redesign aligns Agentless Mode with Test Kitchen's existing mental
model and lifecycle.  The key insight is simple: **a Kitchen instance should be
the thing you are testing**, not a scaffolding machine that manages other things.

By making instances equal to targets, the entire pool/explicit assignment layer,
parallel runner, and shadow driver lifecycle become unnecessary.  The result is
a provisioner that is dramatically simpler to configure, reason about, and debug
— and one that integrates naturally with TK's existing `-c N` parallelism and
`kitchen list` status display.

| | Before | After |
|---|---|---|
| Lines of production code | ~1400 | ~800 |
| Deleted classes | — | 3 (Pool, Explicit, ParallelRunner) |
| New classes | — | 3 (SourceConfig, LocalSourceTransport, SourceNodeDriverAdapter) |
| Tests | 447 | 380 (higher signal-to-noise) |
| Config complexity | High (pool, explicit, parallel, assignment) | Low (1:1 Hash, source block) |
