# Chef Test Kitchen Enterprise — Design Documentation

Reverse-engineered design docs for the `chef-test-kitchen-enterprise` codebase
(analyzed at version **2.0.19**). Read in order, or jump to a topic.

| # | Document | Topic |
| - | -------- | ----- |
| 00 | [Overview](./00-overview.md) | What it is, core mental model, source-tree map |
| 01 | [Architecture](./01-architecture.md) | Layered architecture, module entry point, object graph, concurrency, errors |
| 02 | [Lifecycle & State](./02-lifecycle-and-state.md) | The action FSM, state file, transition/action wrapper, serialization |
| 03 | [Plugin System](./03-plugin-system.md) | Driver/Provisioner/Transport/Verifier bases, dynamic loading, Configurable DSL |
| 04 | [Configuration](./04-configuration.md) | `kitchen.yml`, YAML loader + ERB, DataMunger merge semantics |
| 05 | [CLI & Commands](./05-cli-and-commands.md) | Thor CLI, command classes, dispatch, instance selection |
| 06 | [Enterprise Licensing](./06-enterprise-licensing.md) | Chef Licensing integration — the enterprise delta |
| 07 | [Testing & Build](./07-testing-and-build.md) | Minitest/Cucumber suites, Rake tasks, bundle wrapper, Expeditor |

## TL;DR

Test Kitchen runs the cross-product of **suites × platforms** as **Instances**,
driving each through an ordered lifecycle — `destroy -> create -> converge ->
setup -> verify` — implemented by five swappable plugin subsystems (Driver,
Provisioner, Transport, Verifier, Lifecycle Hooks). Configuration is layered
YAML merged by `DataMunger` into immutable `Instance` objects that run in
parallel. The enterprise fork adds `chef-licensing` enforcement wired in at load
time, after each plugin load, and at converge.
