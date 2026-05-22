# Ex12 Backlog Grooming

This backlog was generated from repository findings and recent crawl changes. Tracker integration is not available in this environment, so this markdown backlog is committed as the source artifact.

## 1. Structured Logging Expansion Across Lifecycle Paths
Priority: High

Problem:
Structured logging is implemented for verifier dummy call flow, but not consistently across other high-signal lifecycle paths.

Code links:
- [lib/kitchen/verifier/dummy.rb](lib/kitchen/verifier/dummy.rb)
- [lib/kitchen/command/action.rb](lib/kitchen/command/action.rb)
- [lib/kitchen/instance.rb](lib/kitchen/instance.rb)

Acceptance criteria:
- Add structured log fields op, status, elapsed_ms to one additional lifecycle path beyond verifier.
- Use consistent field names and value formatting across paths.
- Add tests that assert structured fields are present in log output.
- Update docs with one command for viewing filtered structured logs.

## 2. Validation Parity for Dummy Plugins
Priority: Medium

Problem:
Input validation exists in verifier dummy call boundary, but analogous boundaries in other dummy plugins may diverge.

Code links:
- [lib/kitchen/verifier/dummy.rb](lib/kitchen/verifier/dummy.rb)
- [lib/kitchen/provisioner/dummy.rb](lib/kitchen/provisioner/dummy.rb)
- [lib/kitchen/driver/dummy.rb](lib/kitchen/driver/dummy.rb)
- [spec/kitchen/verifier/dummy_spec.rb](spec/kitchen/verifier/dummy_spec.rb)

Acceptance criteria:
- Add minimal type validation at one additional dummy plugin call boundary.
- Keep behavior backward compatible for valid inputs.
- Add at least one negative test asserting error class and message.
- No regression in existing dummy plugin specs.

## 3. CI Baseline Reliability Improvements
Priority: High

Problem:
Local CI baseline script is present, but style checks are optional due local tool variability; parity and guidance can be improved.

Code links:
- [support/ci-baseline.sh](support/ci-baseline.sh)
- [ai-track-docs/build-test.md](ai-track-docs/build-test.md)
- [.github/workflows/ci.yml](.github/workflows/ci.yml)
- [.expeditor/run_linux_tests.sh](.expeditor/run_linux_tests.sh)

Acceptance criteria:
- Add explicit mode flags documented for quick, standard, and strict runs.
- Ensure strict mode mirrors CI-required checks as closely as local environment allows.
- Include expected runtime and failure guidance in docs.
- Script exits non-zero on required-check failure in all modes.

## 4. Secret Hygiene Hardening and Verification Automation
Priority: High

Problem:
Ignore patterns were expanded for secret-like files, but automated pre-commit or CI validation for secret detection is not yet documented in local workflow.

Code links:
- [.gitignore](.gitignore)
- [SECURITY.md](SECURITY.md)
- [.github/workflows/ci.yml](.github/workflows/ci.yml)

Acceptance criteria:
- Add a documented local secret-scan command sequence in security or build docs.
- Add optional CI baseline flag to run secret scan locally.
- Validate one known risky pattern is caught by scan.
- Keep false positives manageable with documented exclusions.

## 5. Dependency Constraint Follow-Through
Priority: Medium

Problem:
Dependency hygiene notes propose conservative upper bounds, but proposals are not yet triaged into actionable implementation tasks.

Code links:
- [ai-track-docs/dependency-hygiene.md](ai-track-docs/dependency-hygiene.md)
- [Gemfile](Gemfile)
- [chef-test-kitchen-enterprise.gemspec](chef-test-kitchen-enterprise.gemspec)

Acceptance criteria:
- Review and classify each proposed constraint as adopt, defer, or reject with rationale.
- Implement at least one low-risk constraint change without major upgrade.
- Run unit test suite and report compatibility result.
- Update dependency notes with decision log and next review date.
