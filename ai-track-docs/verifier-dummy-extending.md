# Extending Kitchen::Verifier::Dummy

This guide covers small, low-risk ways to extend the dummy verifier in:
- `lib/kitchen/verifier/dummy.rb`

## Module Role
`Kitchen::Verifier::Dummy` is a simulation verifier. It is useful for testing lifecycle flow and plugin behavior without external verifier dependencies.

Current behavior:
- logs verify start/end
- supports optional sleep (`:sleep`)
- supports deterministic fail (`:fail`)
- supports probabilistic fail (`:random_failure`)

## Safe Extension Points
1. Add config flags with `default_config` for optional behavior.
2. Add log detail in `call(state)` without changing control flow.
3. Add helper methods called from `failure_if_set` for clearer branching.
4. Keep `ActionFailed` messages stable when changing failure helpers.

## Example: Add A New Optional Toggle
If you add `default_config :verbose_verify, false`:
1. Read it in `call(state)`.
2. Emit extra `debug` output only when true.
3. Do not change return type or exception behavior.

## Minimal Test Strategy
Use focused unit specs in:
- `spec/kitchen/verifier/dummy_spec.rb`

Recommended checks for each extension:
1. Default config value is set correctly.
2. Positive path works with no exception.
3. Failure path still raises `Kitchen::ActionFailed` when expected.
4. Message text is stable for failure assertions.
5. Logging assertions cover any new debug/info output.

## Validate Changes
Run the focused verifier spec:

```bash
bundle exec ruby -I spec spec/kitchen/verifier/dummy_spec.rb
```

Optionally run all unit tests:

```bash
bundle exec rake unit
```
