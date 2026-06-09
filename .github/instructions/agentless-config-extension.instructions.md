---
applyTo: "lib/kitchen/agentless_context.rb,lib/kitchen/data_munger.rb,lib/kitchen/config.rb,spec/kitchen/agentless*"
---

# Extending the `agentless:` Config Block in TKE Core

## Where agentless config lives in TKE

The `agentless:` block in `kitchen.yml` is parsed by TKE core before the
provisioner sees it. Key files:

| File | Role |
|------|------|
| `lib/kitchen/agentless_context.rb` | Validates + holds the agentless config |
| `lib/kitchen/remote_node.rb` | Data object for one remote node |
| `lib/kitchen/data_munger.rb` | Normalises YAML (ERB, merges suite/platform) |

## Adding a new top-level field to `agentless:`

Example: adding `retry-count:` field.

### 1. Add to `AgentlessContext`

```ruby
# lib/kitchen/agentless_context.rb
module Kitchen
  class AgentlessContext
    # Expose the new field
    attr_reader :retry_count

    def initialize(config)
      @parallel_mode = config.fetch("parallel-mode", "disabled")
      @retry_count   = config.fetch("retry-count", 1).to_i   # NEW
      @remote_nodes  = build_remote_nodes(config["remote_nodes"])
      validate!
    end

    private

    def validate!
      unless @retry_count.is_a?(Integer) && @retry_count >= 1
        raise Kitchen::UserError,
          "agentless.retry-count must be a positive integer, got: #{@retry_count}"
      end
    end
  end
end
```

### 2. Add spec

```ruby
# spec/kitchen/agentless_context_spec.rb
describe "retry-count" do
  it "defaults to 1" do
    ctx = Kitchen::AgentlessContext.new(minimal_config)
    _(ctx.retry_count).must_equal 1
  end

  it "accepts custom value" do
    ctx = Kitchen::AgentlessContext.new(minimal_config.merge("retry-count" => 3))
    _(ctx.retry_count).must_equal 3
  end

  it "raises UserError for zero" do
    cfg = minimal_config.merge("retry-count" => 0)
    _(proc { Kitchen::AgentlessContext.new(cfg) }).must_raise Kitchen::UserError
  end
end
```

### 3. Add to `RemoteNode` (if it's a per-node field)

```ruby
# lib/kitchen/remote_node.rb
class RemoteNode
  attr_reader :name, :mode, :endpoint, :retry_count   # add attr_reader

  def initialize(config)
    @retry_count = (config["retry-count"] || 1).to_i
  end
end
```

## Adding a new `remote_nodes` field

Example: adding `fqdn:` (already exists) or `tags:` (new).

### In `RemoteNode`

```ruby
attr_reader :tags

def initialize(config)
  @tags = config.fetch("tags", [])
end
```

### Validation

```ruby
def validate!
  raise Kitchen::UserError, "tags must be an Array" unless @tags.is_a?(Array)
end
```

## ERB in `remote_nodes`

The `remote_nodes` list supports ERB via the existing `DataMunger` pipeline.
Do NOT bypass `DataMunger` for ERB processing. The `ErbNodeListHelper` class
in KCAI handles dynamic node list generation from ERB.

Example kitchen.yml:
```yaml
agentless:
  remote_nodes: <%= ErbNodeListHelper.nodes_from_file("hosts.txt") %>
```

## Running TKE tests

```bash
cd /path/to/test-kitchen
bundle exec rspec spec/kitchen/agentless_context_spec.rb
bundle exec rspec                   # all specs
bundle exec chefstyle lib/ spec/    # lint
```

## Critical rules

- Never call `instance.state_file` from outside `Instance` — it's private
- `AgentlessContext` raises `Kitchen::UserError` for all config errors
- `RemoteNode` is immutable after construction — no setters
- ERB processing happens in `DataMunger`, not in `AgentlessContext`
