---
applyTo: "**/*"
---

# PR and Git Workflow for Agentless Mode Stories

## Repos involved

This epic spans **two repositories** — always be clear which one you're in
before running git/gh commands:

| Repo | Role |
|------|------|
| `chef/chef-test-kitchen-enterprise` (this repo, "TKE core") | Plugin host: CLI, instance lifecycle, generic driver/provisioner/verifier extension points |
| `chef/kitchen-agentless` ("KCAI") | The actual agentless driver/provisioner/verifier plugin — almost all feature work lives here |

TKE core changes for this epic should be **strictly minimal** (see AGENTS.md
"Permitted TKE Core Changes"). If a change is agentless-specific, it almost
certainly belongs in KCAI, not here.

## Branch naming

| Story type | Branch format |
|-----------|---------------|
| Agentless epic story | `CHEF-XXXXX` or `CHEF-XXXXX-<short-description>` |
| Bug fix | `CHEF-XXXXX-fix-<what>` |
| Multi-repo story | Same branch name in both repos |

## Target branch

- **TKE core**: all feature branches are cut from `agentless-dev-latest`, and all PRs target `agentless-dev-latest` — **never `main` directly**.
- **KCAI**: all feature branches are cut from `agentless-dev-latest`, and all PRs target `agentless-dev-latest`.

```bash
git fetch origin
git checkout agentless-dev-latest
git pull origin agentless-dev-latest
git checkout -b CHEF-XXXXX
```

## Commit format (DCO required)

```bash
git commit --signoff -m "CHEF-XXXXX: <short description>

- What was changed
- Why it was changed
- Any notable decisions"
```

DCO signoff (`--signoff` / `-s`) is **mandatory**. Missing signoff fails CI.
If you forget: `git commit --amend --signoff --no-edit`.

For multi-line commit messages, write the message to a temp file
(`/tmp/commit_msg.txt`) and commit with `git commit --signoff -F /tmp/commit_msg.txt`,
then delete the temp file. This avoids shell-escaping issues with
apostrophes/backticks in commit bodies.

## Ask before opening a PR

Unless the user has explicitly asked for a PR, treat implementation work as
**commit-and-push for review, not PR-and-merge**. Many sessions in this repo
push directly to a feature/integration branch (e.g. `agentless-dev-latest`)
so the user can review real end-to-end test output (`kitchen create` /
`converge` / `verify` against live targets) before a PR is even opened.
**Always confirm with the user before running `gh pr create`** if it wasn't
explicitly requested — do not assume a commit should immediately become a PR.

## PR creation (once approved)

```bash
gh pr create \
  --base agentless-dev-latest \
  --title "CHEF-XXXXX: description" \
  --label "ai-assisted" \
  --body "..."
```

**Required labels**: `ai-assisted` must always be present on AI-assisted PRs.

## PR description template

```html
<h2>Summary</h2>
<p>What this PR implements.</p>

<h2>Jira Story</h2>
<p><a href="https://progresssoftware.atlassian.net/browse/CHEF-XXXXX">CHEF-XXXXX</a></p>

<h2>Changes</h2>
<ul>
  <li><code>lib/kitchen/provisioner/chef_infra_agentless.rb</code> — what changed</li>
  <li><code>spec/kitchen/provisioner/chef_infra_agentless_spec.rb</code> — tests added</li>
</ul>

<h2>Testing</h2>
<ul>
  <li>Unit tests: X new tests, Y% coverage</li>
  <li>Lint: 0 offenses</li>
  <li>End-to-end: kitchen create/converge/verify/destroy verified against a real target</li>
</ul>
```

## Multi-repo PRs

When a story touches both `chef-test-kitchen-enterprise` (TKE core) and
`kitchen-agentless` (KCAI), create PRs in both repos with:
- Same branch name
- Cross-linked PR descriptions
- Both targeting `agentless-dev-latest`

## Expeditor labels

| Change type | Labels to add |
|-------------|--------------|
| New feature | `enhancement`, `Expeditor: Bump Version Minor` |
| Bug fix | `bug` |
| Test/docs only | `Expeditor: Skip Version Bump` |
| Breaking change | `Expeditor: Bump Version Major` |
| Documentation only | `documentation`, `Expeditor: Skip All` |

## Pre-PR checklist

```bash
bundle exec rake unit                           # 0 failures
bundle exec cookstyle --chefstyle lib/ spec/    # 0 offenses (new offenses only —
                                                 # don't fix unrelated pre-existing ones)
bundle exec kitchen destroy && bundle exec kitchen converge && bundle exec kitchen verify
```

All of the above must be green before creating a PR. For KCAI end-to-end
checks, test against **all three target-provisioning styles** if the change
touches credential/endpoint resolution (see
`agentless-config-extension.instructions.md`): real-mode static host,
ephemeral Docker target, ephemeral EC2 target.
