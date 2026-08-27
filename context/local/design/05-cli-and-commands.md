# CLI & Commands

## Entry point

The `kitchen` executable (`bin/kitchen`) boots `Kitchen::CLI`, a
[Thor](https://github.com/rails/thor)-based command-line application defined in
`lib/kitchen/cli.rb`. Thor handles argument parsing, subcommand routing, option
flags, and help generation.

```
bin/kitchen  ->  Kitchen::CLI (Thor)  ->  Kitchen::Command::<Name>  ->  Instance actions
```

## Subcommands

The common subcommands map onto the lifecycle plus operational tooling:

| Subcommand   | Command class            | What it does |
| ------------ | ------------------------ | ------------ |
| `list`       | `Command::List`          | Show instances and their last action/error state |
| `create`     | `Command::Action`        | Run the `create` transition |
| `converge`   | `Command::Action`        | Run up to `converge` |
| `setup`      | `Command::Action`        | Run up to `setup` |
| `verify`     | `Command::Action`        | Run up to `verify` |
| `destroy`    | `Command::Action`        | Run `destroy` |
| `test`       | `Command::Test`          | Full destroy->create->converge->verify->destroy arc |
| `login`      | `Command::Login`         | Open an interactive session on an instance (execs) |
| `exec`       | `Command::Exec`          | Run an arbitrary command on instance(s) |
| `package`    | `Command::Package`       | Ask the driver to produce an image from an instance |
| `diagnose`   | `Command::Diagnose`      | Dump merged config + plugin metadata |
| `doctor`     | `Command::Doctor`        | Ask plugins to self-check for common misconfig |
| `console`    | `Command::Console`       | Interactive Ruby console with Kitchen loaded |
| `license`    | `Command::License`       | **Enterprise:** generate/activate a Chef license |
| `sink`       | `Command::Sink`          | Internal/utility sink command |

## The Command layer (`lib/kitchen/command.rb` + `command/`)

`Kitchen::Command::Base` is the shared superclass for every subcommand. It is
constructed by the CLI with:

- `cmd_args` — leftover positional args (e.g. an instance regex).
- `cmd_options` — parsed Thor flags.
- `options` — wiring context: the `:action` name, a `:help` callable, the
  `:config` (a `Kitchen::Config`), the `:loader`, and the Thor `:shell`.

Dispatch flows through the `PerformCommand` mixin on the CLI:

```ruby
def perform(task, command, args = nil, additional_options = {})
  require "kitchen/command/#{command}"
  klass = Kitchen::Command.const_get(Thor::Util.camel_case(command))
  klass.new(args, options, { action: task, config: @config, ... }).call
end
```

So each Thor subcommand method is a thin shim that calls
`perform(<task>, <command_file>)`; the real work lives in the command class's
`#call`.

## Instance selection

Most action commands accept an optional **regexp** argument to select a subset
of instances (e.g. `kitchen converge ubuntu` runs only instances whose name
matches `/ubuntu/`). The command asks the `Config` for its instance
`Collection` and filters with `get_all(regex)`; with no argument it operates on
all instances. Actions across the selected instances run concurrently (subject
to the `no_parallel_for` mutexes described in `02-lifecycle-and-state.md`),
bounded by a max-concurrency cap.

## Action commands (`command/action.rb`)

`Command::Action` is the generic driver for the five lifecycle transitions. It
resolves the target instances, then invokes the matching action method
(`create`, `converge`, `setup`, `verify`, `destroy`) on each, which delegates
into the Instance FSM. `Command::Test` wraps the full arc with destroy-mode
semantics.

## Error surfacing

Commands rely on the error taxonomy (`errors.rb`): `UserError`s produce clean,
actionable messages; `InstanceFailure`/`ActionFailed` are aggregated so a run
across many instances reports every failure and points at
`.kitchen/logs/<instance>.log` for detail, then exits non-zero.
