# Ex11 PR Hygiene Draft

## Proposed PR Summary
This PR adds a reusable PR-hygiene draft for the crawl workflow, including clear review focus, risk framing, verification steps, rollback guidance, and improved commit-message patterns.

## Review Focus
- Confirm the summary maps directly to actual file changes.
- Verify risk statements are specific and proportional to change scope.
- Ensure verification steps are runnable as written.
- Check rollback instructions map to an exact commit.

## Risks
- Primary risk: process/documentation drift if templates are copied without updating file paths or evidence.
- Secondary risk: inconsistent commit style across sequential crawl exercises.
- Runtime risk: low (docs/process-only change).

## Verification Steps
1. Read and validate the PR template content in this file.
2. Run formatting/markdown lint if your workflow requires it.
3. Confirm commit and branch metadata:
   - `git log --oneline -n 5`
   - `git status --short`

## Rollback
- Revert commit for this PR branch:
  - `git revert <ex11_commit_sha>`

## Ready-To-Paste PR Body Template
Summary: Add PR-hygiene template with review focus, risks, verification, rollback, and improved commit-message examples.

Review Focus:
- Accuracy of scope-to-files mapping
- Evidence quality and reproducibility
- Rollback clarity

Risk: Low (documentation/process only)

Verification:
- `git log --oneline -n 5`
- `git status --short`

Rollback: `git revert <ex11_commit_sha>`

## Commit Message Improvements (Proposals)
Recent messages are clear but can be more uniform and actionable with scope + impact.

Suggested pattern:
- `<type>(crawl): exN <topic> [scope]`

Examples for recent commits:
- Current: `GHCP: Crawl Ex10 CI baseline`
  - Proposed: `docs(crawl): ex10 add local CI baseline script and usage notes`
- Current: `GHCP: Crawl Ex9 structured logging`
  - Proposed: `feat(verifier): ex9 add structured verify logs with op/status/elapsed_ms`
- Current: `GHCP: Crawl Ex8 security and secret hygiene`
  - Proposed: `security(crawl): ex8 tighten secret ignore rules and security guidance`
- Current: `GHCP: Crawl Ex7 dependency hygiene notes`
  - Proposed: `docs(deps): ex7 document critical dependencies and safe constraint proposals`
- Current: `GHCP: Crawl Ex6 performance baseline`
  - Proposed: `perf(verifier): ex6 add micro-benchmark baseline and variance notes`

## Message Quality Checklist
- Starts with intent (`feat`, `fix`, `docs`, `perf`, `security`, `test`)
- Includes scope when helpful (`verifier`, `deps`, `crawl`)
- States user-visible effect, not only task label
- Avoids ambiguous terms like "updates" without context
