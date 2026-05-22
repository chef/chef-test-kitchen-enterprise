# Static Analysis Baseline (Ex14)

Linting/static-analysis checks already exist in CI and are strict enough for routine work.

## Current Checks in CI
Defined in `.github/workflows/lint.yml`:
- Ruby style: `cookstyle --chefstyle --display-cop-names`
- YAML lint: `yamllint`
- Markdown lint: `markdownlint-cli2`
- Markdown link checks
- Unit tests in lint workflow (`bundle exec rake unit --trace`)

## Local Run Commands
### Ruby static analysis (full)
```bash
bundle exec cookstyle --chefstyle --display-cop-names
```

### Ruby static analysis (targeted path)
```bash
bundle exec cookstyle --chefstyle --display-cop-names lib/kitchen/verifier/dummy.rb spec/kitchen/verifier/dummy_spec.rb
```

### YAML lint
```bash
yamllint .
```

### Markdown lint
```bash
npx markdownlint-cli2 "*.md"
```

### Unit test gate used by lint workflow
```bash
bundle exec rake unit --trace
```

## Current Targeted Path Result
Targeted cookstyle run for verifier path:
- Files: `lib/kitchen/verifier/dummy.rb`, `spec/kitchen/verifier/dummy_spec.rb`
- Result: `2 files inspected, no offenses detected`

## Practical Notes
- Prefer targeted lint during development, then run full lint before PR.
- If local lint tooling is missing, install the relevant tool and rerun with `bundle exec` where applicable.
