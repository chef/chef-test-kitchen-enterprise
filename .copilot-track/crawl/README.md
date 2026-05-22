# Crawl Notes

This folder stores prompts and artifacts for iterative repository crawl work.

## Chain PRs
- Keep crawl work in small, sequenced PRs.
- Each PR should have one clear scope (for example docs scaffold, architecture map, command matrix).
- Link each PR to the prior one to preserve review context and decision history.

## Evidence in PRs
- Include command evidence used to validate changes (for example test/style commands and key output snippets).
- Call out what was inspected and what was intentionally excluded.
- Add before/after references for any generated diagrams or docs updates.

## Prompt Usage
- Store reusable crawl prompts in this folder (or a subfolder) and version them with the PR.
- Keep prompts explicit about scope boundaries, exclusions, and expected output format.
- Prefer short, composable prompts over one long prompt; chain them across PRs when needed.
