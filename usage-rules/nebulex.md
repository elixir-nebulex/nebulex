# Nebulex Project-Specific Usage Rules

These rules are for agents working on the Nebulex core and adapter
repositories. User-facing documentation lives in `guides/` (published at
<https://hexdocs.pm/nebulex>) and in module docs; do not duplicate it here.
Sections marked "(core repo only)" describe the core package and are context
in adapter repos; see "Scope" in `workflow.md`.

## Project Overview

Nebulex is a caching abstraction for Elixir, in the spirit of Ecto for
databases. The core package provides:

- The `Nebulex.Cache` API and the `Nebulex.Adapter.*` behaviours that
  adapters implement.
- Declarative decorator-based caching (`Nebulex.Caching`) inspired by the
  Spring Cache Abstraction.
- Telemetry instrumentation for every cache command.
- The Observable API (`register_event_listener/2`) and
  `Nebulex.Event.CacheEntryEvent`, which the external `nebulex_streams`
  package uses for distributed invalidation.

Adapters (local, partitioned, multilevel, coherent, Redis, Cachex, disk LFU,
etc.) are separate Hex packages. The "Adapters" guide
(`guides/introduction/nbx-adapters.md`, <https://hexdocs.pm/nebulex/nbx-adapters.html>)
is the single source of truth for the adapter list; do not maintain a
parallel list in rule files.

## Adapter Repo Layout

Adapter repos follow this shape (see `nebulex_local` and
`nebulex_distributed`):

| Path | Purpose |
|------|---------|
| `lib/nebulex/adapters/<name>.ex` | The adapter: `@behaviour Nebulex.Adapter` plus KV, CompositeKV, and the optional behaviours it supports, and `__before_compile__/1` |
| `lib/nebulex/adapters/<name>/options.ex` | NimbleOptions schemas and `validate_*_opts!` functions for the adapter's own options |
| `test/shared/` | Adapter-specific `deftests` suites |
| `test/support/` | Test caches for the adapter |
| `test/test_helper.exs` | Loads core's `test/support/*.exs` and shared suites from the `nebulex` checkout |

Core's `test/support/` and `test/shared/` are not in the Hex package.
Adapter repos fetch them with `mix nbx.setup` and run tests with
`NEBULEX_PATH=nebulex mix test` (CI does the same); the repo's `AGENTS.md`
has the exact commands.

## Dependencies

- Core requires only `:nimble_options`; `:decorator` (needed for
  `Nebulex.Caching`) and `:telemetry` are optional. Adapters require
  `:nebulex` plus their backend dependencies.
- Keep dependencies minimal and well-justified; prefer the standard library.
- Use optional dependencies for non-core features.
- Put new deps under the existing comment groups of the repo's `mix.exs`.

## Cache Definition

- Caches are defined with `use Nebulex.Cache` and the `:otp_app` and
  `:adapter` options.
- Compile-time adapter options go under `adapter_opts`, never at the top
  level of `use Nebulex.Cache`. The options are a NimbleOptions schema, so
  a top-level `primary_storage_adapter` raises at compile time.

```elixir
defmodule MyApp.PartitionedCache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Partitioned,
    adapter_opts: [primary_storage_adapter: Nebulex.Adapters.Local]
end
```

- In tests, use the caches defined in `test/support/` instead of defining
  new ones unless the test needs a specific configuration.

## Adapter Pattern

- All adapters MUST implement the `Nebulex.Adapter` behaviour, including
  `c:init/1` returning `{:ok, child_spec, adapter_meta}` and the
  `__before_compile__/1` macro callback.
- Adapters MUST implement `Nebulex.Adapter.KV` and
  `Nebulex.Adapter.CompositeKV`; `use Nebulex.Cache` validates both at
  compile time. `use Nebulex.Adapter.CompositeKV` provides default,
  non-atomic implementations of the callbacks `get_and_update/6`,
  `update/7`, `fetch_or_store/6`, and `get_or_store/6` (backing the
  `Nebulex.Cache` functions `get_and_update/3`, `update/4`,
  `fetch_or_store/3`, and `get_or_store/3`). Override them to change where
  the given function runs or the atomicity guarantees.
- Implement optional behaviours as needed: `Nebulex.Adapter.Queryable`,
  `Nebulex.Adapter.Transaction`, `Nebulex.Adapter.Observable`,
  `Nebulex.Adapter.Info` (`use Nebulex.Adapters.Common.Info` gives the
  default implementation).
- Follow each callback's documented return contract (see "Return Value
  Conventions"). For example, `init/1` returns
  `{:ok, child_spec, adapter_meta}`; `KV.delete/3` returns `:ok`; and
  `Queryable.execute/3` with `:delete_all` returns `{:ok, count}`. Both
  deletion callbacks can return `{:error, reason}`.
- Options reach the adapter mixed with Nebulex's own options. Never
  validate the whole keyword list strictly. On `init/1`, drop the cache
  compile and start options first:
  `Keyword.drop(opts, Nebulex.Cache.Options.__compile_opts__() ++ Nebulex.Cache.Options.__start_opts__())`.
  In command callbacks, `Keyword.take/2` the adapter's own keys before
  `NimbleOptions.validate!/2`, or drop the shared runtime options with
  `Keyword.drop(opts, Nebulex.Cache.Options.__runtime_shared_opts__())`.
- Options an adapter consumes from a command's `opts` are documented in
  that adapter's module docs; options every adapter must honor are
  documented in the `Nebulex.Adapter.<Feature>` callback `@doc`.
- `Nebulex.Adapters.Nil` (core) is the reference implementation; use it as
  a template for callback shapes and error wrapping. The "Creating a new
  adapter" guide (<https://hexdocs.pm/nebulex/creating-new-adapter.html>)
  is the user-facing walkthrough; keep its callback signatures in sync
  with the behaviours.

## Command Pattern (core repo only)

- Use `defcommand/2` from `Nebulex.Adapter` to build public command wrappers
  and `defcommandp/2` for private ones.
- Command functions run through `Nebulex.Adapter.run_command/4`, which
  validates the shared runtime options, emits the Telemetry span, and wraps
  the response.
- The first parameter of a command is always `name` (the cache name or PID);
  the last is always `opts` (keyword list).

```elixir
defcommand fetch(name, key, opts)
defcommandp do_put(name, key, value, on_write, ttl, keep_ttl?, opts), command: :put
```

## Return Value Conventions

- Read operations that can fail MUST return `{:ok, value}` or
  `{:error, %Nebulex.KeyError{}}` for missing keys.
- Write operations MUST return `{:ok, true}` for success or `{:ok, false}` for
  conditional failures (e.g., `put_new`).
- Single-key deletes (`delete/3`) return `:ok` whether or not the key
  existed; query deletes (`execute/3` with `:delete_all`) return
  `{:ok, count}`.
- NEVER return bare `:error` atoms; always use `{:error, reason}` tuples.
- Since v3, `nil` is a valid cache value. Never treat `nil` as a cache-miss
  sentinel. In `get_and_update/3`, returning `{current, nil}` stores `nil`;
  return `:pop` to remove the entry.
- Do not add options whose only effect reproduces another function's
  `on_write` mode (`put_new`, `replace`); point users to that function.

### Bang Functions (core repo only)

Adapters never define bang functions; `use Nebulex.Cache` generates them.

- Bang functions MUST use `unwrap_or_raise/1` from `Nebulex.Utils`.
- Functions that return `:ok` have bang versions that also return `:ok`.
- Functions that return `{:ok, boolean}` have bang versions that return the
  boolean.

```elixir
def fetch!(name, key, opts) do
  unwrap_or_raise fetch(name, key, opts)
end

def put!(name, key, value, opts) do
  _ = unwrap_or_raise do_put(name, key, value, :put, opts)

  :ok
end
```

### Composite Operations

`fetch_or_store/3`, `get_or_store/3`, `get_and_update/3`, and `update/4` are
composite operations dispatched to the adapter's `Nebulex.Adapter.CompositeKV`
callbacks. The adapter decides where the given function runs and what
atomicity it provides. `fetch_or_store/3` propagates a fallback
`{:error, reason}` without caching; `get_or_store/3` stores the fallback's
return value as-is. Composite operations emit their own Telemetry command
span in addition to the spans of the primitive commands they trigger.

## Options and Validation (core repo only)

- Every public option set is a NimbleOptions schema in
  `Nebulex.Cache.Options` (cache) or `Nebulex.Caching.Options`
  (decorators). The schema generates the docs; validation is a separate
  step:
  - Options consumed by the cache layer are popped with
    `pop_and_validate_timeout!/3`, `pop_and_validate_boolean!/3`, or
    `pop_and_validate_integer!/3`.
  - Options that stay in `opts` and reach the adapter are validated with a
    `validate_<fn>_opts!/1` function (take the keys, `NimbleOptions.validate!/2`,
    return `opts`), e.g. `validate_runtime_shared_opts!/1`.
- Validate options at the beginning of the function, before any work.
- `put_options_docs/0` is spliced into the docs of `put/3` and the four
  composite operations. An option that applies to a single function needs
  its own schema and `_options_docs/0` function; never let a function
  document an option it ignores.
- All cache functions accept the shared `:telemetry`, `:telemetry_event`, and
  `:telemetry_metadata` options.

```elixir
# lib/nebulex/cache/kv.ex (simplified)
defp do_put(name, key, value, on_write, opts) do
  {ttl, opts} = Options.pop_and_validate_timeout!(opts, :ttl)
  {keep_ttl?, opts} = Options.pop_and_validate_boolean!(opts, :keep_ttl, on_write == :replace)

  do_put(name, key, value, on_write, ttl, keep_ttl?, opts)
end
```

## Decorators

Decorators (`cacheable`, `cache_put`, `cache_evict`) are implemented in
`Nebulex.Caching.Decorators` (core). The macro captures key expressions and
option lambdas as AST at compile time; all runtime resolution happens in
`Nebulex.Caching.Decorators.Runtime`. The "Declarative caching" guide
(<https://hexdocs.pm/nebulex/declarative-caching.html>) is the user-facing
reference; the rules below are what matters when writing or reviewing
decorated code.

- `use Nebulex.Caching` accepts module-level defaults: `:cache`,
  `:default_key_generator`, `:on_error` (`:nothing` or `:raise`, default
  `:nothing`), `:transaction`, `:match`, and `:opts`.
- Decorate a single-clause function. For multi-clause logic, decorate a
  wrapper and delegate to a private multi-clause function.
- Always provide an explicit `:key`; do not rely on default key generation.
  For computed keys use a module capture: `key: &MyModule.generate_key/1`.
- Prefer module captures over anonymous functions for `:match`, `:key`,
  `:references`, and `:query`, and keep captured data small; fetch large
  values inside the function body.
- `cacheable` is read-through; combine with `:references` when one value
  must be reachable from several keys, and use `:match` to validate the
  reference. External references use the `Nebulex.Caching.keyref/2` macro:
  `references: &(&1 && keyref(&1.id, cache: OtherCache))`. Give references
  a TTL or an explicit eviction path; dangling references are a bug.
- `cache_put` is write-through; always pair it with `:match` so failures
  (`{:error, _}`) are not cached. Never put `cache_put` and `cacheable` on
  the same function.
- `cache_evict` supports `key: {:in, keys}` for several keys,
  `all_entries: true`, `before_invocation: true`, and `:query` for match-spec
  based eviction.
- `transaction: true` wraps the function and cache operations in a
  transaction to prevent races and stampedes; use it deliberately because
  it serializes access to the key.
- `:match` functions return `true`, `false`, `{true, value}`, or
  `{true, value, opts}`; nothing else. Removed v2 options: `:keys` (use
  `key: {:in, keys}`) and `:key_generator` (use a `:key` capture or the
  `use`-level `:default_key_generator`).

```elixir
@decorate cacheable(key: id)
def get_user(id), do: do_get_user(id)

@decorate cacheable(key: email, references: &(&1 && &1.id), match: &match_email(&1, email))
def get_user_by_email(email), do: Repo.get_by(User, email: email)

@decorate cache_put(key: user.id, match: &match_ok/1)
def update_user(user, attrs), do: user |> User.changeset(attrs) |> Repo.update()

@decorate cache_evict(key: {:in, [user.id, user.email]})
def delete_user(user), do: Repo.delete(user)

defp do_get_user(nil), do: nil
defp do_get_user(id), do: Repo.get(User, id)

defp match_email(%{email: email}, email), do: true
defp match_email(_, _), do: false

defp match_ok({:ok, user}), do: {true, user}
defp match_ok({:error, _}), do: false
```

## Observable API

- Core exposes `register_event_listener/2` and `unregister_event_listener/2`
  (plus bang variants) via `Nebulex.Cache.Observable`, backed by
  `Nebulex.Telemetry.CacheEntryHandler`, which converts command Telemetry
  events into `%Nebulex.Event.CacheEntryEvent{}` structs with type
  `:inserted`, `:updated`, `:deleted`, or `:expired`.
- Adapters that emit their own entry events implement
  `Nebulex.Adapter.Observable`.
- Distributed invalidation (`Nebulex.Streams`, the Coherent adapter) lives in
  the `nebulex_streams` and `nebulex_distributed` packages, not in core.

## Telemetry

- Every command emits a span through `Nebulex.Adapter.run_command/4` when the
  `:telemetry` option is `true` (the default). The event name is
  `telemetry_prefix ++ [:command]`, and `:telemetry_prefix` defaults to the
  cache module name as atoms (`MyApp.Cache` becomes `[:my_app, :cache]`).
- Span metadata always includes `:adapter_meta`, `:command`, `:args`, and
  `:extra_metadata` (from `:telemetry_metadata`); the stop event adds
  `:result`. Do not remove or rename these keys.
- `[:nebulex, :cache, :init]` is emitted by `Nebulex.Cache.Supervisor` when
  a cache starts; it is the only fixed-name event.
- `:telemetry_event` overrides the event name per call; `:telemetry_metadata`
  adds user metadata.
- Adapters may emit extra events but must not suppress or rename the core
  ones.
- Document every new event in the module docs with its measurements and
  metadata keys.

## Error Handling

- `Nebulex.Error` is the general cache error, `Nebulex.KeyError` is for
  missing keys, `Nebulex.CacheNotFoundError` for dynamic cache lookup
  failures, and `Nebulex.QueryError` for invalid queries.
- Wrap errors with `wrap_error/2` from `Nebulex.Utils`; include `:reason`,
  `:command`, and `:key` where applicable and preserve the original error in
  `:reason`.
- Bang functions raise the wrapped exception via `unwrap_or_raise/1`; never
  raise for control flow in non-bang functions.

```elixir
# From Nebulex.Adapters.Nil
wrap_error Nebulex.KeyError, key: key

# From Nebulex.Adapter.CompositeKV
wrap_error Nebulex.Error, reason: reason, command: :fetch_or_store, key: key
```

## Testing

### Test Structure

- Shared suites use `deftests do ... end` from `Nebulex.CacheCase` (core
  `test/support/cache_case.exs`). In core they live in `test/shared/` and
  run against `Nebulex.TestAdapter` through `test/nebulex/cache_test.exs`;
  adapter repos run the same suites plus their own.
- A behavioural test in core's `test/shared/` is a contract every adapter
  must satisfy. For an option adapters may ignore, put the validation test
  in `test/shared/` and the behavioural test in `test/nebulex/` against
  `Nebulex.TestAdapter` (and update that adapter to implement it).
- Group related tests in `describe` blocks named after the function
  (`describe "put/3"`).
- Receive the cache under test from the context: `%{cache: cache}`.
- Start processes with `start_supervised!/1` so they are cleaned up between
  tests; to check that a process died, use `Process.monitor/1`, not
  `Process.alive?/1`.
- Test success and error paths, the bang and non-bang variants, and edge
  values: `nil`, `true`, `false`, empty collections.
- Shared test data goes in module attributes or fixture functions, not
  repeated literals.

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

- Assertions follow "Testing" in `elixir-style.md`: expression under test
  on the left, expected value on the right, `==` when the expected value is
  fully known.
- Use `assert_raise ErrorType, ~r"message pattern"` for exceptions.

## Documentation Standards

### Line Length

- Code is formatted by `mix format` at 100 columns (`.formatter.exs`).
- Prose in `@moduledoc`, `@doc`, `@typedoc`, and code comments wraps at 80
  columns. This is a convention enforced in review, not by tooling.
- Exceptions: a line containing a link may exceed 80 columns, and a code
  snippet inside docs may exceed it by one or two characters. A longer
  snippet must be reformatted with the Elixir formatter.

### Module and Function Documentation

- Every module has a `@moduledoc` (or `@moduledoc false` if internal). Every
  public function has `@doc` and `@spec`; every custom type has `@typedoc`.
  In core, `mix doctor` enforces 100% `@moduledoc` and at least 80% `@doc`
  coverage (`.doctor.exs`); `@spec` is enforced in review.
- Options defined with NimbleOptions are documented by inserting the
  generated docs, e.g. `#{Nebulex.Cache.Options.start_link_options_docs()}`;
  do not hand-write option lists that duplicate a schema.
- Include usage examples in module docs and doctests in function docs when
  practical.
- In core, group related functions with `@doc group: "Group Name"` (see
  `lib/nebulex/cache.ex`).
- Document Telemetry events with their measurements and metadata keys.
- A new public option or a callback change must also be reflected in the
  guides that show it (core `guides/`: `creating-new-adapter.md` for
  callbacks, `getting-started.md` for the cache API).

### Code Comments

- Avoid obvious comments; use them for non-obvious logic only.
- Use a single `#` for comments and `##` for section separators
  (`## API`, `## Private functions`).
- Mark internal functions and modules with `@doc false` / `@moduledoc false`.
- Use `# Inline common instructions` followed by
  `@compile inline: [function_name: arity]` for hot-path helpers.

## Elixir Specifics

- Do not introduce new macros when a function will do. Reuse what the repo
  already has (core: `defcacheapi`, `defcommand`, decorators; adapters: the
  behaviour's `__before_compile__/1` and any DSL the adapter already ships).
- One module per file. Core's `lib/nebulex/exceptions.ex` deliberately
  groups the exception modules; do not extend that exception to other files.
- The `in` operator in guards needs a compile-time list or range on the
  right (`when x in [1, 2, 3]`, `when x in 1..10`); a variable raises
  `ArgumentError`.
- Never add a dependency unless asked; the standard library covers dates,
  times, and most utilities.
- `mix nbx.gen.cache -c MyApp.Cache` is the only generator. It takes only
  the `--cache`/`-c` option and always emits `Nebulex.Adapters.Local`.

## Naming Conventions

- Adapter modules: `Nebulex.Adapters.*`. Behaviour modules:
  `Nebulex.Adapter.<Feature>`. User cache modules: `<App>.Cache` or
  `<App>.<Context>Cache`.
- Public API functions are short verbs (`fetch/2`, `put/3`, `delete/2`,
  `has_key?/2`); bang versions add `!`; private helpers are prefixed with
  `do_`; predicates end in `?`.
- Variables: `cache`, `adapter_meta`, `opts`, `key`/`keys`, `value`/`values`,
  `ttl`.

## Backward Compatibility

- New options must have defaults so existing callers keep working.
- Deprecate before removal and document the migration path (core
  `guides/upgrading/`, <https://hexdocs.pm/nebulex/v3-0.html>).
- Breaking changes to `Nebulex.Cache`, `Nebulex.Caching`, or any
  `Nebulex.Adapter.*` callback require a major version (see
  `architecture.md` Non-Negotiable #2).
- Removed v2 APIs, for reference when reading old code or issues: the
  `all/2` callback (now `get_all/2` with a query spec), the decorator
  `:keys` and `:key_generator` options, and `nil` as a cache-miss sentinel.
  Adapter packages document their own renames (e.g. the multilevel
  `inclusion_policy` option in `nebulex_distributed`).
