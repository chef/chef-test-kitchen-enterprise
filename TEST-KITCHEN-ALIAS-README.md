# test-kitchen (Alias Gem)

This is an alias/shim gem that provides backward compatibility for gems that depend on `test-kitchen`.

## Purpose

The `test-kitchen` gem has been superseded by `chef-test-kitchen-enterprise`. This alias gem allows existing gems with transitive dependencies on `test-kitchen` to seamlessly use `chef-test-kitchen-enterprise` as a drop-in replacement.

## How It Works

When you install the `test-kitchen` gem, it automatically installs `chef-test-kitchen-enterprise` as a dependency. All functionality is provided by `chef-test-kitchen-enterprise`.

## Usage

### For End Users

Simply install as you normally would:

```shell
gem install test-kitchen
```

Or in your Gemfile:

```ruby
gem "test-kitchen"
```

The `chef-test-kitchen-enterprise` gem will be installed automatically.

### For Gem Authors

If your gem depends on `test-kitchen`, users can install this alias gem to satisfy the dependency without any code changes needed in your gem.

## Migration

If you're actively maintaining a gem, consider updating your dependency to use `chef-test-kitchen-enterprise` directly:

```ruby
# In your gemspec
spec.add_dependency "chef-test-kitchen-enterprise", "~> 1.0"
```

## More Information

For full documentation and usage instructions, see the [chef-test-kitchen-enterprise README](README.md) or visit [https://kitchen.ci/](https://kitchen.ci/).

