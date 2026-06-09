---
name: create-kitchen-plugin
description: 'Create a new Test Kitchen plugin or plugin scaffold. Use when creating a Kitchen driver plugin, a Kitchen provisioner plugin, a new kitchen-* repository, or when deciding whether provisioner work belongs in kitchen-chef-enterprise versus a separate premium plugin repo. Includes repo naming, gem naming, GitHub workflow, and Expeditor setup rules.'
argument-hint: 'Describe the plugin type, plugin name, premium status if provisioner, and any target repo constraints.'
user-invocable: true
---

# Create Kitchen Plugin

## What This Skill Does

This skill creates or scaffolds a new Test Kitchen plugin using the Chef Test Kitchen conventions in this workspace.

It handles three cases:

1. Driver plugin: create a new repository named `kitchen-<plugin-name>`.
2. Non-premium provisioner plugin: extend `kitchen-chef-enterprise` instead of creating a new repository.
3. Premium provisioner plugin: create a separate plugin repository and scaffold it to match the enterprise plugin layout.

The resulting repo, gem name, module layout, CI workflows, and Expeditor config must match the established patterns used by Chef Test Kitchen repositories, especially `chef/kitchen-chef-enterprise` for plugin-repo automation and release plumbing.

## When To Use

Use this skill when the request includes any of these intents or keywords:

- Create a new Kitchen plugin
- Scaffold a Kitchen driver
- Scaffold a Kitchen provisioner
- Create a `kitchen-...` repository
- Add a premium Kitchen provisioner plugin
- Add GitHub workflows or Expeditor config for a new Kitchen plugin repo

Do not use this skill for small edits inside an existing plugin unless the request also includes repo bootstrapping or plugin creation.

## Inputs To Collect

Before writing files, determine these inputs from the user request or ask only for the missing ones:

- Plugin type: `driver` or `provisioner`
- Plugin name: normalized kebab-case suffix used in repo and gem naming
- Premium status for provisioners: `premium` or `non-premium`
- Target location: existing repo or new repo
- Whether the user wants full repo scaffolding or only the plugin implementation slice

## Decision Flow

### Driver Plugin

If the plugin type is `driver`:

1. Create a new repository named `kitchen-<plugin-name>`.
2. Set the gem name to `kitchen-<plugin-name>`.
3. Align repository structure and packaging conventions with `chef-test-kitchen-enterprise` and existing Kitchen plugin repos.
4. Add GitHub workflows and `.expeditor/` configuration that match `chef/kitchen-chef-enterprise`.

### Provisioner Plugin

If the plugin type is `provisioner`:

1. Determine whether it is premium.
2. If it is non-premium, do not create a new repo. Add the implementation to `kitchen-chef-enterprise`.
3. If it is premium, create a separate plugin repository and scaffold it with the same workflow and Expeditor baseline used by `chef/kitchen-chef-enterprise`.

## Procedure

### 1. Confirm the Controlling Case

Reduce the request to one of these mutually exclusive outcomes:

- New driver repo
- Existing non-premium provisioner work in `kitchen-chef-enterprise`
- New premium provisioner repo

If the request does not clearly state whether a provisioner is premium, stop and ask that question before editing.

### 2. Inspect the Baseline Before Editing

Read only the minimum files needed to match the existing conventions.

For all cases:

- Review [AGENTS.md](../../../AGENTS.md) for Kitchen-specific conventions in this workspace.
- Inspect the relevant gemspec, module layout, and test structure in the target repo.

For new repos:

- Inspect the GitHub workflow files used by `chef/kitchen-chef-enterprise`.
- Inspect `.expeditor/config.yml` and `.expeditor/verify.pipeline.yml` in `chef/kitchen-chef-enterprise`.
- Mirror those files closely unless the user requests a deliberate deviation.

### 3. Create the Repository Skeleton

For a new plugin repo, create the minimum baseline expected for a Kitchen plugin repository:

- `README.md`
- `LICENSE`
- `NOTICE` if the source pattern uses it
- `Gemfile`
- `<repo-name>.gemspec`
- `Rakefile`
- `.github/workflows/`
- `.expeditor/`
- `lib/`
- `spec/`

Use the plugin type to shape the Ruby entrypoints:

- Driver plugin: `lib/kitchen/driver/<plugin_name>.rb`
- Provisioner plugin: `lib/kitchen/provisioner/<plugin_name>.rb`

Also add the top-level entry file under `lib/` that requires the plugin implementation and follows the established naming pattern.

### 4. Apply Naming Rules

Use consistent names across all surfaces.

- Repository: `kitchen-<plugin-name>` for all new driver repos
- Gem: `kitchen-<plugin-name>` unless the target repo already establishes a different convention
- Main Ruby file names: snake_case version of the plugin name
- Ruby module names: CamelCase version of the plugin name nested under the correct Kitchen namespace

For provisioners that remain inside `kitchen-chef-enterprise`, preserve that repo's existing gem and module structure instead of forcing a new `kitchen-...` gem.

### 5. Add CI And Release Plumbing

For any new repository, copy the workflow and release-management baseline from `chef/kitchen-chef-enterprise`.

At minimum, create equivalents of the standard files present there:

- `.github/workflows/ci.yml`
- `.github/workflows/lint.yml`
- `.github/workflows/integration.yml`
- `.github/workflows/allchecks.yml`
- `.expeditor/config.yml`
- `.expeditor/verify.pipeline.yml`

If the baseline repo includes helper scripts under `.expeditor/`, copy the same pattern and update only repo-specific names or commands.

Do not invent a different CI layout when an existing enterprise plugin baseline already exists.

### 6. Implement The Plugin Slice

Create the smallest useful plugin scaffold that matches Test Kitchen plugin conventions.

For drivers:

- Add the plugin class under `Kitchen::Driver`
- Register the correct plugin API version and plugin version pattern used by the baseline repo
- Add a minimal configuration surface and lifecycle stubs

For provisioners:

- Add the plugin class under `Kitchen::Provisioner`
- Follow the existing provisioner base class pattern in the target repo
- Add only the minimal config and command construction needed for the requested plugin scaffold

### 7. Add Tests With Matching Structure

Mirror the spec layout used by the target repo.

- New repo: create spec files that match the plugin file layout
- Existing `kitchen-chef-enterprise` work: place specs alongside the existing provisioner specs in that repo

Cover at least:

- Plugin loads successfully
- Default config behavior
- One representative positive path
- One representative validation or error path

### 8. Validate Before Stopping

Run the narrowest useful checks for the touched repo.

- Unit tests for the new plugin spec files
- Lint or style checks used by the target repo
- Any narrow load-path or require check for the new gem entrypoint

For new repos, confirm these are consistent before finishing:

- Repo name matches gem name where required
- Main require paths match file names
- Workflow filenames exist and reference the new repo correctly
- Expeditor config is present and internally consistent

## Quality Bar

The work is only complete when all of the following are true:

- The plugin is routed to the correct place based on plugin type and premium status.
- New repos use `kitchen-<plugin-name>` naming where required by this workflow.
- Non-premium provisioners are kept in `kitchen-chef-enterprise`.
- New repos include GitHub workflow files and Expeditor config matching the `chef/kitchen-chef-enterprise` baseline.
- Ruby file layout, gem naming, and module naming are internally consistent.
- At least one focused validation step has been run.

## Ambiguities To Resolve Early

Ask a focused question if any of these remain unclear:

- For a provisioner, is this premium or non-premium?
- For a premium provisioner repo, should the repo name still be `kitchen-<plugin-name>` or should it follow a `kitchen-chef-...` convention?
- Does the user want full repository scaffolding or only the plugin implementation inside an existing repo?
- Which existing repo should be treated as the source of truth if `chef-test-kitchen-enterprise` and `kitchen-chef-enterprise` differ?

## Example Prompts

- `/create-kitchen-plugin Create a new Kitchen driver plugin named ec2spot as a new repo.`
- `/create-kitchen-plugin Scaffold a premium Kitchen provisioner plugin named chef-orchestrator in a separate repo.`
- `/create-kitchen-plugin Add a non-premium provisioner named chef-local into kitchen-chef-enterprise and include tests.`