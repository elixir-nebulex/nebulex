# Nebulex Project-Specific Usage Rules

## Project Overview

Nebulex is a fast, flexible, and extensible caching library for Elixir that provides:
- Multiple cache adapters (local, distributed, multilevel, partitioned)
- Declarative decorator-based caching inspired by Spring Cache Abstraction
- OTP design patterns and fault tolerance
- Telemetry instrumentation
- Support for TTL, eviction policies, transactions, and more

## Architecture Patterns

### Cache Definition

- Caches MUST be defined using `use Nebulex.Cache` with `:otp_app` and `:adapter` options
- Caches should be started in the application supervision tree, not manually
- Use descriptive cache module names that indicate their purpose (e.g., `MyApp.LocalCache`, `MyApp.UserCache`)

**Example**:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local
end
```

### Adapter Pattern

- All adapters MUST implement the `Nebulex.Adapter` behaviour
- Adapters MUST implement `c:init/1` returning `{:ok, child_spec, adapter_meta}`
- Adapter functions MUST return `{:ok, value}` or `{:error, reason}` tuples
- Use `wrap_error/2` from `Nebulex.Utils` to wrap errors consistently
- Implement optional behaviours as needed: `Nebulex.Adapter.KV`, `Nebulex.Adapter.Queryable`, etc.
- Leverage `use Nebulex.Adapter.Transaction` and similar modules for default implementations

### Command Pattern

- Use `defcommand/2` macro from `Nebulex.Adapter` to build public command wrappers
- Use `defcommandp/2` for private command wrappers
- Command functions automatically handle telemetry, metadata, and error wrapping
- The first parameter to commands should always be `name` (the cache name or PID)
- The last parameter should always be `opts` (keyword list)

**Example**:

```elixir
defcommand fetch(name, key, opts)
defcommandp do_put(name, key, value, on_write, ttl, keep_ttl?, opts), command: :put
```

## Return Value Conventions

### Tuple Returns

- Read operations that can fail MUST return `{:ok, value}` or `{:error, %Nebulex.KeyError{}}` for missing keys
- Write operations MUST return `{:ok, true}` for success or `{:ok, false}` for conditional failures (e.g., `put_new`)
- Delete operations MUST return `:ok` regardless of whether the key existed
- NEVER return bare `:error` atoms; always use `{:error, reason}` tuples

### Bang Functions

- Provide bang versions (`!`) of functions that unwrap `{:ok, value}` or raise exceptions
- Bang functions MUST use `unwrap_or_raise/1` from `Nebulex.Utils`
- Functions that return `:ok` should have bang versions that also return `:ok`
- Functions that return `{:ok, boolean}` should have bang versions that return the boolean

**Example**:

```elixir
def fetch!(name, key, opts) do
  unwrap_or_raise fetch(name, key, opts)
end

def put!(name, key, value, opts) do
  _ = unwrap_or_raise do_put(name, key, value, :put, opts)
  :ok
end
```

## Options and Validation

### Options Handling

- Use `Nebulex.Cache.Options` module for option validation
- Call `Options.validate_runtime_shared_opts!/1` to validate runtime options
- Use `Options.pop_and_validate_timeout!/2` for TTL and timeout options
- Use `Options.pop_and_validate_boolean!/2` for boolean options
- Use `Options.pop_and_validate_integer!/2` for integer options
- Validate options as early as possible, preferably at the beginning of the function

**Example**:

```elixir
def put(name, key, value, opts) do
  {ttl, opts} = Options.pop_and_validate_timeout!(opts, :ttl)
  {keep_ttl?, opts} = Options.pop_and_validate_boolean!(opts, :keep_ttl, false)

  do_put(name, key, value, :put, ttl, keep_ttl?, opts)
end
```

### Shared Options

- All cache functions should accept `:telemetry`, `:telemetry_event`, and `:telemetry_metadata` options
- Support lifecycle hooks: `:before` and `:after_return` for adapter-specific hooks
- Document adapter-specific options clearly in the module documentation

## Decorators

### Decorator Usage

- Use `use Nebulex.Caching` to enable decorator support in a module
- Configure default cache via `use Nebulex.Caching, cache: MyCache`
- Always use decorators on functions, not on function heads with multiple clauses
- Prefer module captures over anonymous functions for better performance: `match: &__MODULE__.match_fun/1`
- Avoid capturing large data structures in decorator lambdas

**Invalid**:

```elixir
@decorate cacheable(key: id)
def get_user(nil), do: nil

def get_user(id) do
  # logic
end
```

**Valid**:

```elixir
@decorate cacheable(key: id)
def get_user(id) do
  do_get_user(id)
end

defp do_get_user(nil), do: nil
defp do_get_user(id) do
  # logic
end
```

### Decorator Options

- Use `:key` option to specify explicit cache keys; avoid relying solely on default key generation
- Use `:references` for implementing cache key references and memory-efficient caching
- Use `:match` option to conditionally cache values (e.g., `match: &match_fun/1`)
- Use `:on_error` option to control error handling (`:raise` or `:nothing`)
- Specify TTL via `:opts` option: `opts: [ttl: :timer.hours(1)]`

### `cacheable` Decorator

- Use `@decorate cacheable` for read-through caching patterns
- Combine with `:references` option when the same value needs multiple cache keys
- Use `:match` function with references to ensure consistency (e.g., validating email matches)

**Example**:

```elixir
@decorate cacheable(key: id)
def get_user(id) do
  Repo.get(User, id)
end

@decorate cacheable(key: email, references: &(&1 && &1.id), match: &match_email(&1, email))
def get_user_by_email(email) do
  Repo.get_by(User, email: email)
end

defp match_email(%{email: email}, email), do: true
defp match_email(_, _), do: false
```

### `cache_put` Decorator

- Use `@decorate cache_put` for write-through caching patterns
- Always use `:match` option to conditionally update cache (e.g., only on `{:ok, value}`)
- Avoid using `cache_put` and `cacheable` on the same function

**Example**:

```elixir
@decorate cache_put(key: user.id, match: &match_ok/1)
def update_user(user, attrs) do
  user
  |> User.changeset(attrs)
  |> Repo.update()
end

defp match_ok({:ok, user}), do: {true, user}
defp match_ok({:error, _}), do: false
```

### `cache_evict` Decorator

- Use `@decorate cache_evict` for cache invalidation
- Use `key: {:in, keys}` to evict multiple keys at once
- Use `:all_entries` option to clear the entire cache
- Use `:before_invocation` option to evict before function execution
- Use `:query` option for complex eviction patterns based on match specifications

**Example**:

```elixir
@decorate cache_evict(key: {:in, [user.id, user.email]})
def delete_user(user) do
  Repo.delete(user)
end

@decorate cache_evict(all_entries: true)
def clear_all_users do
  Repo.delete_all(User)
end

@decorate cache_evict(query: &__MODULE__.query_for_tag/1)
def delete_by_tag(tag) do
  # Delete logic
end

def query_for_tag(%{args: [tag]}) do
  [{:entry, :"$1", %{tag: :"$2"}, :_, :_}, [{:"=:=", :"$2", tag}], [true]]
end
```

## Testing Patterns

### Test Structure

- Use `deftests do` macro for shared test suites that can run across multiple adapters
- Structure tests with `describe` blocks grouping related functionality
- Use context fixtures with `%{cache: cache}` for test setup
- Test both successful and error scenarios for each function

**Example**:

```elixir
defmodule MyAdapterTest do
  import Nebulex.CacheCase

  deftests do
    describe "put/3" do
      test "puts the given entry into the cache", %{cache: cache} do
        assert cache.put(:key, :value) == :ok
        assert cache.fetch!(:key) == :value
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise NimbleOptions.ValidationError, fn ->
          cache.put(:key, :value, ttl: "invalid")
        end
      end
    end
  end
end
```

### Test Assertions

- Use `assert cache.function() == expected_value` for exact equality
- Use `assert_raise ErrorType, ~r"message pattern"` for exception testing
- Test edge cases: `nil`, boolean values (`true`, `false`), empty collections
- Test both normal and bang (`!`) versions of functions
- Avoid pattern matching in assertions when the full value is known (use direct equality)

**Invalid**:

```elixir
assert {:ok, value} = cache.fetch(:key)
```

**Valid**:

```elixir
assert cache.fetch(:key) == {:ok, expected_value}
```

## Telemetry

### Telemetry Events

- Emit telemetry events for all cache commands when `:telemetry` option is `true`
- Use `:telemetry_prefix` option to customize event names (defaults to `[:cache_name, :cache]`)
- Provide comprehensive metadata: `:adapter_meta`, `:command`, `:args`, `:result`
- Support custom `:telemetry_event` and `:telemetry_metadata` options per command

### Telemetry Best Practices

- Use `Nebulex.Telemetry.span/3` for span events (start, stop, exception)
- Include measurements like `:duration` and `:system_time`
- Document all telemetry events in module documentation with measurement and metadata keys
- Provide example telemetry handlers in documentation

## Error Handling

### Error Types

- Use `Nebulex.Error` for general cache errors
- Use `Nebulex.KeyError` for missing key errors
- Use `Nebulex.CacheNotFoundError` for dynamic cache lookup failures
- Wrap adapter-specific errors using `wrap_error/2` from `Nebulex.Utils`

### Error Wrapping

- Adapter functions should wrap errors consistently using `wrap_error/2`
- Include relevant context in error metadata (`:key`, `:command`, `:reason`)
- Preserve original error information in the `:reason` field

**Example**:

```elixir
def fetch(_adapter_meta, key, opts) do
  case do_fetch(key) do
    {:ok, value} -> {:ok, value}
    {:error, :not_found} -> wrap_error Nebulex.KeyError, key: key
    {:error, reason} -> wrap_error Nebulex.Error, reason: reason, command: :fetch, key: key
  end
end
```

## Performance Considerations

### Key Generation

- Provide explicit keys in decorators when possible; avoid relying on default key generation
- For complex keys, use module captures: `key: &MyModule.generate_key/1`
- Keep captured data in decorator lambdas small; fetch large configs inside functions

### Reference Keys

- Use cache key references (`:references` option) to avoid storing duplicate values
- Store references in a local cache and values in a remote cache (e.g., Redis) for optimization
- Set TTL for references to prevent dangling keys
- Use external references with `keyref(key, cache: AnotherCache)` for cross-cache references

### Optimization

- Use `Stream` for large result sets instead of loading all data at once
- Leverage `Task.async_stream/3` for concurrent cache operations when appropriate
- Set appropriate TTL values to balance freshness and performance
- Use `put_all/2` for batch operations instead of multiple `put/3` calls

## Documentation Standards

### Module Documentation

- Start with a clear `@moduledoc` explaining the purpose and main features
- Include usage examples in module documentation
- Document all compile-time options
- Document all runtime shared options
- Provide telemetry event documentation with measurements and metadata

### Function Documentation

- Use `@doc` for all public functions
- Include `@typedoc` for all custom types
- Provide examples in function documentation using doctests when applicable
- Document all options with descriptions and default values
- Group related functions using `@doc group: "Group Name"`

### Code Comments

- Avoid obvious comments; code should be self-explanatory
- Use comments for complex algorithms or non-obvious business logic
- Mark internal functions with `@doc false` or `@moduledoc false`
- Use `# Inline common instructions` followed by `@compile {:inline, function_name: arity}`

## Naming Conventions

### Modules

- Adapter modules: `Nebulex.Adapters.*` (e.g., `Nebulex.Adapters.Local`)
- Cache modules: `<App>.Cache` or `<App>.<Context>Cache` (e.g., `MyApp.Cache`, `MyApp.UserCache`)
- Behaviour modules: `Nebulex.Adapter.<Feature>` (e.g., `Nebulex.Adapter.KV`)

### Functions

- Use descriptive function names: `fetch/2`, `put/3`, `delete/2`, `has_key?/1`
- Bang versions: `fetch!/2`, `put!/3`, `delete!/2`
- Private helpers: prefix with `do_` (e.g., `do_fetch/3`, `do_put/7`)
- Predicate functions: suffix with `?` (e.g., `has_key?/1`, `expired?/2`)

### Variables

- Cache instance: `cache`
- Adapter metadata: `adapter_meta`
- Options: `opts`
- Keys: `key` or `keys`
- Values: `value` or `values`
- TTL: `ttl`

## Code Organization

### File Structure

- Main cache API: `lib/nebulex/cache.ex`
- Adapter behaviour: `lib/nebulex/adapter.ex`
- Adapter implementations: `lib/nebulex/adapters/<adapter_name>.ex`
- Cache features: `lib/nebulex/cache/<feature>.ex`
- Decorators: `lib/nebulex/caching/decorators.ex`
- Mix tasks: `lib/mix/tasks/<task_name>.ex`

### Module Grouping

- Keep related functionality together (e.g., all KV operations in `Nebulex.Cache.KV`)
- Use nested modules for options, helpers, and internal implementation details
- Separate public API from internal implementation

## Common Pitfalls to Avoid

- **Do NOT** use decorators on multi-clause functions without proper wrapper functions
- **Do NOT** forget to validate options at the beginning of functions
- **Do NOT** return inconsistent error types; always use tuples or raise exceptions via bang functions
- **Do NOT** capture large data structures in decorator lambdas
- **Do NOT** forget to handle `nil`, boolean, and edge case values in tests
- **Do NOT** use `cache_put` and `cacheable` decorators on the same function
- **Do NOT** forget to evict cache references when using `:references` option; use TTL or explicit eviction
- **Do NOT** implement adapter callbacks without proper error wrapping
- **Do NOT** skip telemetry support in adapter implementations
- **Do NOT** use pattern matching in test assertions when the full value is known

## Backward Compatibility

- Maintain backward compatibility when adding new options (use default values)
- Deprecate old APIs before removal; provide migration path in documentation
- Follow semantic versioning strictly: major version for breaking changes
- Test against multiple Elixir and OTP versions in CI

## Dependencies

- Keep dependencies minimal and well-justified
- Prefer standard library solutions over external dependencies
- Use optional dependencies for non-core features
- Document all dependencies in README with their purpose
