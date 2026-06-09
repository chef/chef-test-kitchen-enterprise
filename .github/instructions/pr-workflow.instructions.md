---
applyTo: "**/*"
---

# PR and Git Workflow for Agentless Mode Stories

## Branch naming

| Story type | Branch format |
|-----------|---------------|
| Agentless epic story | `CHEF-XXXXX-<short-description>` |
| Bug fix | `CHEF-XXXXX-fix-<what>` |
| Multi-repo story | Same branch name in both repos |

## Target branch

**All agentless work targets `agentless-dev`, NOT `main`.**

```bash
git checkout agentless-dev
git pull origin agentless-dev
git checkout -b CHEF-27350-my-story
```

## Commit format (DCO required)

```bash
git commit --signoff -m "CHEF-XXXXX: <short description>

- What was changed
- Why it was changed
- Any notable decisions"
```

DCO signoff (`--signoff` / `-s`) is **mandatory**. Missing signoff fails CI.
If you forget: `git commit --amend --signoff --no-edit`

## PR creation

```bash
gh pr create \
  --base agentless-dev \
  --title "[CHEF-XXXXX] Short description" \
  --label "ai-assisted" \
  --label "enhancement" \
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
  <li><code>lib/kitchen/agentless/foo.rb</code> — what changed</li>
  <li><code>spec/kitchen/agentless/foo_spec.rb</code> — tests added</li>
</ul>

<h2>Testing</h2>
<ul>
  <li>Unit tests: X new tests, Y% coverage</li>
  <li>Lint: 0 offenses</li>
  <li>End-to-end: kitchen create/converge/destroy verified</li>
</ul>
```

## Multi-repo PRs

When a story touches both `test-kitchen` (TKE core) and
`kitchen-chef-infra-agentless` (KCAI), create PRs in both repos with:
- Same branch name
- Cross-linked PR descriptions
- Both targeting `agentless-dev`

## Expeditor labels

| Change type | Labels to add |
|-------------|--------------|
| New feature | `enhancement`, `Expeditor: Bump Version Minor` |
| Bug fix | `bug` |
| Test/docs only | `Expeditor: Skip Version Bump` |
| Breaking change | `Expeditor: Bump Version Major` |

## Pre-PR checklist

```bash
bundle exec rake unit                           # 0 failures
bundle exec cookstyle --chefstyle lib/ spec/   # 0 offenses
bundle exec kitchen destroy && bundle exec kitchen converge   # green end-to-end
```

All three must be green before creating a PR.
