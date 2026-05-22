# Build and Test

## Prerequisites
- Ruby version compatible with the repository Gemfile
- Bundler installed

## Setup
```bash
bundle install
```

## Common Commands
```bash
# Run full test suite
bundle exec rake test

# Unit-focused tests
bundle exec rake unit

# Integration features
bundle exec rake features

# Style and quality checks
bundle exec rake style
bundle exec rake quality

# Project stats / coverage indicators
bundle exec rake stats
```

## Focused Iteration
```bash
# Run a single spec file
bundle exec ruby -I spec spec/path/to/file_spec.rb

# Run a single cucumber feature
bundle exec cucumber features/some_feature.feature
```

## Practical CI Parity Tips
- Prefer `bundle exec` for all Ruby tooling.
- Run `rake quality` before opening a PR.
- Include failing and passing command output snippets in PR evidence when relevant.
