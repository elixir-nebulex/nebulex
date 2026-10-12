# Creating a new adapter

This guide walks you through creating a custom Nebulex adapter. We start by
creating a new project, make the shared tests pass, and end up with a simple
in-memory adapter. It is loosely based on
[`Nebulex.Adapters.Redis`](https://github.com/elixir-nebulex/nebulex_redis_adapter/),
so you can use that repo as an example.

## Mix Project

Nebulex's main repo contains shared tests we are going to use. The version
published to Hex does not contain test code, so we need to check out Nebulex
from GitHub. We start by creating a new project.

```console
mix new nebulex_memory_adapter
```

Now let's modify `mix.exs` so that we can fetch the Nebulex repository. The
shared tests use `mimic` and `stream_data`, so we add them as test
dependencies too.

```elixir
defmodule NebulexMemoryAdapter.MixProject do
  use Mix.Project

  @nbx_vsn "3.1.0"
  @version "0.1.0"

  def project do
    [
      app: :nebulex_memory_adapter,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      nebulex_dep(),
      {:telemetry, "~> 0.4 or ~> 1.0", optional: true},

      # Used by the Nebulex shared tests
      {:mimic, "~> 2.0", only: :test},
      {:stream_data, "~> 1.2", only: :test}
    ]
  end

  defp nebulex_dep do
    if path = System.get_env("NEBULEX_PATH") do
      {:nebulex, "~> #{@nbx_vsn}", path: path}
    else
      {:nebulex, "~> #{@nbx_vsn}"}
    end
  end

  defp aliases do
    [
      "nbx.setup": [
        "cmd rm -rf nebulex",
        "cmd git clone --depth 1 --branch v#{@nbx_vsn} https://github.com/elixir-nebulex/nebulex"
      ]
    ]
  end
end
```

The guide needs Nebulex 3.1 or later, because the
`Nebulex.Adapter.CompositeKV` behaviour used below is new in 3.1.

We define a `mix nbx.setup` task that fetches a Nebulex version into the
folder given by the `NEBULEX_PATH` environment variable. Let's run it.

```console
export NEBULEX_PATH=nebulex
mix nbx.setup
```

Now is a good time to fetch the other dependencies.

```console
mix deps.get
```

## Tests

Before we implement the adapter, let's set up the tests.

First, it helps to know which adapter behaviours there are:

- `Nebulex.Adapter.KV` - Required. Key-value operations like `fetch`, `put`,
  `delete`, and so on.
- `Nebulex.Adapter.CompositeKV` - Required. Provides the callbacks behind
  `get_and_update/3`, `update/4`, `fetch_or_store/3`, and `get_or_store/3`.
  Add `use Nebulex.Adapter.CompositeKV` to get the default implementation,
  or implement the callbacks yourself to control where the given function
  runs or what atomicity you provide.
- `Nebulex.Adapter.Queryable` - Optional. Query operations like `delete_all`
  and `get_all` with filters. Recommended for most adapters.
- `Nebulex.Adapter.Transaction`, `Nebulex.Adapter.Info`,
  `Nebulex.Adapter.Observable` - Optional. See the Adapter API docs.

In this guide we implement `KV` and `Queryable`, and use the default
`CompositeKV` implementation. Let's start by defining a cache that uses our
adapter in `test/support/test_cache.ex`

```elixir
defmodule NebulexMemoryAdapter.TestCache do
  use Nebulex.Cache,
    otp_app: :nebulex_memory_adapter,
    adapter: NebulexMemoryAdapter
end
```

We won't write the tests ourselves. Instead, we use the shared tests from the
Nebulex repo. `Nebulex.CacheTestCase` pulls in one suite per behaviour, and
its `:only` option lets us pick the ones we implement, `KV` and `Queryable`.
Let's write `test/nebulex_memory_adapter_test.exs`. The `setup` callback
starts the cache process and puts the `cache` and `name` keys into the test
context, which is what the shared tests read.

```elixir
defmodule NebulexMemoryAdapterTest do
  use ExUnit.Case, async: true
  use Nebulex.CacheTestCase, only: [Nebulex.Cache.KVTest, Nebulex.Cache.QueryableTest]

  alias NebulexMemoryAdapter.TestCache, as: Cache

  setup do
    _pid = start_supervised!(Cache)

    {:ok, cache: Cache, name: Cache}
  end
end
```

The test files from the Nebulex checkout are not compiled automatically, so
we load them in `test/test_helper.exs` before starting ExUnit.

```elixir
# Nebulex dependency path
nbx_dep_path = Mix.Project.deps_paths()[:nebulex]

# Test helpers (Nebulex.CacheCase and the test adapters)
for file <- File.ls!("#{nbx_dep_path}/test/support"), file != "test_cache.exs" do
  Code.require_file("#{nbx_dep_path}/test/support/" <> file, __DIR__)
end

# One shared suite per behaviour
for file <- File.ls!("#{nbx_dep_path}/test/shared/cache") do
  Code.require_file("#{nbx_dep_path}/test/shared/cache/" <> file, __DIR__)
end

# Nebulex.CacheTestCase
Code.require_file("#{nbx_dep_path}/test/shared/cache_test_case.exs", __DIR__)

ExUnit.start()
```

Now let's run the tests to see what we need to implement.

```console
mix test
== Compilation error in file test/support/test_cache.ex ==
** (NimbleOptions.ValidationError) invalid value for :adapter option: the module NebulexMemoryAdapter was not compiled, ensure it is correct and it is included as a project dependency
    test/support/test_cache.ex:2: (module)
```

The adapter module does not exist yet. `use Nebulex.Cache` validates the
adapter at compile time, so nothing runs until we have one.

## Implementation

We go step by step: the base `Nebulex.Adapter` behaviour first, then the
required `Nebulex.Adapter.KV` and `Nebulex.Adapter.CompositeKV` behaviours,
and finally the optional `Nebulex.Adapter.Queryable` behaviour.

> **Note**: For a complete reference implementation with the exact callback
> signatures, see the
> [Nebulex.TestAdapter](https://github.com/elixir-nebulex/nebulex/blob/main/test/support/test_adapter.exs)
> source code. This guide shows the structure and the flow; refer to
> `TestAdapter` for the details.

### Step 1: Implement Nebulex.Adapter

First, let's implement the base `Nebulex.Adapter` behaviour in
`lib/nebulex_memory_adapter.ex`. It is just two callbacks: `init/1` returns
the child spec of the process that holds the data (an `Agent` with a map)
and the adapter metadata, and `__before_compile__/1` lets the adapter inject
code into the cache module, which we don't need.

```elixir
defmodule NebulexMemoryAdapter do
  @behaviour Nebulex.Adapter

  @impl Nebulex.Adapter
  defmacro __before_compile__(_env), do: :ok

  @impl Nebulex.Adapter
  def init(_opts) do
    child_spec = Supervisor.child_spec({Agent, fn -> %{} end}, id: {Agent, 1})

    {:ok, child_spec, %{}}
  end
end
```

Now test to see if the adapter loads:

```console
mix test
== Compilation error in file test/support/test_cache.ex ==
** (NimbleOptions.ValidationError) invalid value for :adapter option: Nebulex.Cache expects the option value NebulexMemoryAdapter to list Nebulex.Adapter.KV as a behaviour
    test/support/test_cache.ex:2: (module)
```

The error tells us we need to implement `Nebulex.Adapter.KV`.

### Step 2: Implement the required KV behaviours

The `Nebulex.Adapter.KV` behaviour provides the key-value operations:
`fetch`, `put`, `delete`, and so on. `Nebulex.Adapter.CompositeKV` is
required as well; `use Nebulex.Adapter.CompositeKV` gives you its default
implementation on top of the KV callbacks. Nebulex passes the started
process as `adapter_meta.pid`, so every callback reads or updates the
`Agent`.

A few details matter for the shared tests. `fetch/3` returns
`Nebulex.KeyError` on a miss, `delete/3` returns the bare `:ok` (not
`{:ok, :ok}`), and the `on_write` argument of `put/7` and `put_all/5`
distinguishes `put` from `put_new` and `replace`. Entries never expire here,
so `ttl/3` returns `:infinity` for a key that exists.

```elixir
defmodule NebulexMemoryAdapter do
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.KV

  use Nebulex.Adapter.CompositeKV

  import Nebulex.Utils

  @impl Nebulex.Adapter
  defmacro __before_compile__(_env), do: :ok

  @impl Nebulex.Adapter
  def init(_opts) do
    child_spec = Supervisor.child_spec({Agent, fn -> %{} end}, id: {Agent, 1})

    {:ok, child_spec, %{}}
  end

  ## Nebulex.Adapter.KV

  @impl Nebulex.Adapter.KV
  def fetch(adapter_meta, key, _opts) do
    case Agent.get(adapter_meta.pid, &Map.fetch(&1, key)) do
      {:ok, value} -> {:ok, value}
      :error -> wrap_error Nebulex.KeyError, key: key
    end
  end

  @impl Nebulex.Adapter.KV
  def put(adapter_meta, key, value, on_write, ttl, keep_ttl?, opts)

  def put(adapter_meta, key, value, :put_new, ttl, keep_ttl?, opts) do
    if exists?(adapter_meta, key) do
      false
    else
      put(adapter_meta, key, value, :put, ttl, keep_ttl?, opts)

      true
    end
    |> wrap_ok()
  end

  def put(adapter_meta, key, value, :replace, ttl, keep_ttl?, opts) do
    if exists?(adapter_meta, key) do
      put(adapter_meta, key, value, :put, ttl, keep_ttl?, opts)

      true
    else
      false
    end
    |> wrap_ok()
  end

  def put(adapter_meta, key, value, _on_write, _ttl, _keep_ttl?, _opts) do
    Agent.update(adapter_meta.pid, &Map.put(&1, key, value))

    {:ok, true}
  end

  @impl Nebulex.Adapter.KV
  def put_all(adapter_meta, entries, on_write, ttl, opts)

  def put_all(adapter_meta, entries, :put_new, ttl, opts) do
    keys = Enum.map(entries, &elem(&1, 0))

    if Enum.any?(keys, &exists?(adapter_meta, &1)) do
      false
    else
      put_all(adapter_meta, entries, :put, ttl, opts)

      true
    end
    |> wrap_ok()
  end

  def put_all(adapter_meta, entries, _on_write, _ttl, _opts) do
    entries = Map.new(entries)

    Agent.update(adapter_meta.pid, &Map.merge(&1, entries))

    {:ok, true}
  end

  @impl Nebulex.Adapter.KV
  def delete(adapter_meta, key, _opts) do
    # Returns `:ok`, not `{:ok, :ok}`
    Agent.update(adapter_meta.pid, &Map.delete(&1, key))
  end

  @impl Nebulex.Adapter.KV
  def take(adapter_meta, key, _opts) do
    with {:ok, value} <- fetch(adapter_meta, key, []) do
      :ok = delete(adapter_meta, key, [])

      {:ok, value}
    end
  end

  @impl Nebulex.Adapter.KV
  def update_counter(adapter_meta, key, amount, default, _ttl, _opts) do
    adapter_meta.pid
    |> Agent.get_and_update(fn state ->
      state = Map.update(state, key, default + amount, &(&1 + amount))

      {Map.fetch!(state, key), state}
    end)
    |> wrap_ok()
  end

  @impl Nebulex.Adapter.KV
  def has_key?(adapter_meta, key, _opts) do
    wrap_ok exists?(adapter_meta, key)
  end

  @impl Nebulex.Adapter.KV
  def ttl(adapter_meta, key, _opts) do
    # Entries never expire in this adapter
    with {:ok, _value} <- fetch(adapter_meta, key, []) do
      {:ok, :infinity}
    end
  end

  @impl Nebulex.Adapter.KV
  def expire(adapter_meta, key, _ttl, _opts) do
    wrap_ok exists?(adapter_meta, key)
  end

  @impl Nebulex.Adapter.KV
  def touch(adapter_meta, key, _opts) do
    wrap_ok exists?(adapter_meta, key)
  end

  ## Private functions

  defp exists?(adapter_meta, key) do
    Agent.get(adapter_meta.pid, &Map.has_key?(&1, key))
  end
end
```

Running the tests again:

```console
mix test
< ... >

  1) test get_all!/2 ok: matches all cached entries (NebulexMemoryAdapterTest)
     test/nebulex_memory_adapter_test.exs:8
     ** (UndefinedFunctionError) function NebulexMemoryAdapter.TestCache.get_all!/0 is undefined or private. Did you mean:
         * get/1
         * get/2
         * put_all!/1
         * put_all!/2
         * put_all!/3
     code: _pid = start_supervised!(Cache)
     stacktrace:
       NebulexMemoryAdapter.TestCache.get_all!()
       test/nebulex_memory_adapter_test.exs:8: (test)

< ... >

Finished in 0.1 seconds (0.1s async, 0.00s sync)

Result: 61/95 passed
Failed: 34 tests
```

All 61 KV tests pass. The 34 failures are the Queryable tests: `get_all!`,
`count_all!`, `delete_all!`, and `stream!` are not even defined on the cache,
because `use Nebulex.Cache` only generates the query API when the adapter
lists `Nebulex.Adapter.Queryable` as a behaviour.

### Step 3: Add Nebulex.Adapter.Queryable (Optional)

Now we add the optional `Nebulex.Adapter.Queryable` behaviour to support
`get_all`, `count_all`, `delete_all`, and `stream`. Nebulex hands the
adapter a `query_meta` map with the operation (`:op`), the entries to match
(`:query`), and the fields to return (`:select`). The two query values every
adapter should support are `{:q, nil}` for all the entries and `{:in, keys}`
for the given keys. Here is the complete adapter:

```elixir
defmodule NebulexMemoryAdapter do
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.KV
  @behaviour Nebulex.Adapter.Queryable

  use Nebulex.Adapter.CompositeKV

  import Nebulex.Utils

  @impl Nebulex.Adapter
  defmacro __before_compile__(_env), do: :ok

  @impl Nebulex.Adapter
  def init(_opts) do
    child_spec = Supervisor.child_spec({Agent, fn -> %{} end}, id: {Agent, 1})

    {:ok, child_spec, %{}}
  end

  ## Nebulex.Adapter.KV

  @impl Nebulex.Adapter.KV
  def fetch(adapter_meta, key, _opts) do
    case Agent.get(adapter_meta.pid, &Map.fetch(&1, key)) do
      {:ok, value} -> {:ok, value}
      :error -> wrap_error Nebulex.KeyError, key: key
    end
  end

  @impl Nebulex.Adapter.KV
  def put(adapter_meta, key, value, on_write, ttl, keep_ttl?, opts)

  def put(adapter_meta, key, value, :put_new, ttl, keep_ttl?, opts) do
    if exists?(adapter_meta, key) do
      false
    else
      put(adapter_meta, key, value, :put, ttl, keep_ttl?, opts)

      true
    end
    |> wrap_ok()
  end

  def put(adapter_meta, key, value, :replace, ttl, keep_ttl?, opts) do
    if exists?(adapter_meta, key) do
      put(adapter_meta, key, value, :put, ttl, keep_ttl?, opts)

      true
    else
      false
    end
    |> wrap_ok()
  end

  def put(adapter_meta, key, value, _on_write, _ttl, _keep_ttl?, _opts) do
    Agent.update(adapter_meta.pid, &Map.put(&1, key, value))

    {:ok, true}
  end

  @impl Nebulex.Adapter.KV
  def put_all(adapter_meta, entries, on_write, ttl, opts)

  def put_all(adapter_meta, entries, :put_new, ttl, opts) do
    keys = Enum.map(entries, &elem(&1, 0))

    if Enum.any?(keys, &exists?(adapter_meta, &1)) do
      false
    else
      put_all(adapter_meta, entries, :put, ttl, opts)

      true
    end
    |> wrap_ok()
  end

  def put_all(adapter_meta, entries, _on_write, _ttl, _opts) do
    entries = Map.new(entries)

    Agent.update(adapter_meta.pid, &Map.merge(&1, entries))

    {:ok, true}
  end

  @impl Nebulex.Adapter.KV
  def delete(adapter_meta, key, _opts) do
    # Returns `:ok`, not `{:ok, :ok}`
    Agent.update(adapter_meta.pid, &Map.delete(&1, key))
  end

  @impl Nebulex.Adapter.KV
  def take(adapter_meta, key, _opts) do
    with {:ok, value} <- fetch(adapter_meta, key, []) do
      :ok = delete(adapter_meta, key, [])

      {:ok, value}
    end
  end

  @impl Nebulex.Adapter.KV
  def update_counter(adapter_meta, key, amount, default, _ttl, _opts) do
    adapter_meta.pid
    |> Agent.get_and_update(fn state ->
      state = Map.update(state, key, default + amount, &(&1 + amount))

      {Map.fetch!(state, key), state}
    end)
    |> wrap_ok()
  end

  @impl Nebulex.Adapter.KV
  def has_key?(adapter_meta, key, _opts) do
    wrap_ok exists?(adapter_meta, key)
  end

  @impl Nebulex.Adapter.KV
  def ttl(adapter_meta, key, _opts) do
    # Entries never expire in this adapter
    with {:ok, _value} <- fetch(adapter_meta, key, []) do
      {:ok, :infinity}
    end
  end

  @impl Nebulex.Adapter.KV
  def expire(adapter_meta, key, _ttl, _opts) do
    wrap_ok exists?(adapter_meta, key)
  end

  @impl Nebulex.Adapter.KV
  def touch(adapter_meta, key, _opts) do
    wrap_ok exists?(adapter_meta, key)
  end

  ## Nebulex.Adapter.Queryable

  @impl Nebulex.Adapter.Queryable
  def execute(adapter_meta, query_meta, _opts)

  def execute(adapter_meta, %{op: :get_all} = query_meta, _opts) do
    wrap_ok Agent.get(adapter_meta.pid, &select(&1, query_meta))
  end

  def execute(adapter_meta, %{op: :count_all} = query_meta, _opts) do
    wrap_ok Agent.get(adapter_meta.pid, &map_size(matches(&1, query_meta)))
  end

  def execute(adapter_meta, %{op: :delete_all} = query_meta, _opts) do
    adapter_meta.pid
    |> Agent.get_and_update(fn state ->
      matched = matches(state, query_meta)

      {map_size(matched), Map.drop(state, Map.keys(matched))}
    end)
    |> wrap_ok()
  end

  @impl Nebulex.Adapter.Queryable
  def stream(adapter_meta, query_meta, _opts) do
    # A list is a valid enumerable; a real adapter would return a lazy stream
    wrap_ok Agent.get(adapter_meta.pid, &select(&1, query_meta))
  end

  ## Private functions

  defp exists?(adapter_meta, key) do
    Agent.get(adapter_meta.pid, &Map.has_key?(&1, key))
  end

  # All the entries, or only the ones for the given keys
  defp matches(state, %{query: {:q, nil}}), do: state
  defp matches(state, %{query: {:in, keys}}), do: Map.take(state, keys)

  defp select(state, %{select: select} = query_meta) do
    entries = matches(state, query_meta)

    case select do
      :key -> Map.keys(entries)
      :value -> Map.values(entries)
      {:key, :value} -> Map.to_list(entries)
    end
  end
end
```

One last run:

```console
mix test
< ... >

Finished in 0.1 seconds (0.1s async, 0.00s sync)

Result: 95 passed
```

This is not a useful adapter for production, but it is the minimum that
passes the KV and Queryable shared suites, and a starting point for your
own adapter. It ignores TTLs, it only understands the two shared query
values, and it does not support the `:entry` select.

## Next Steps

Now that you have a working adapter, you can:

1. Expand the KV behaviour. Implement `ttl/3`, `expire/4`, and `touch/3` for
   real if your adapter supports TTL, honor the `ttl` and `keep_ttl?`
   arguments of `put/7`, and run the `Nebulex.Cache.KVExpirationTest` suite.
2. Add more Queryable operations. Support adapter-specific `{:q, query}`
   values and the `:entry` select, and return an error for queries you do
   not support (see `Nebulex.Cache.QueryableQueryErrorTest`).
3. Add the optional behaviours. Implement `Transaction`, `Info`, or
   `Observable` as needed (see the Adapter API docs), and add their suites to
   the `:only` list.
4. Replace the `Agent` storage with calls to your backend (Redis, Memcached,
   a database, and so on).
5. Write tests specific to your adapter, beyond the shared Nebulex tests.

## Recommended Reading

- [Nebulex.TestAdapter](https://github.com/elixir-nebulex/nebulex/blob/main/test/support/test_adapter.exs):
  the reference implementation Nebulex itself uses for testing. It shows the
  exact callback signatures and return values for KV and Queryable, and how
  to handle TTL, entry validation, and errors.
- [Nebulex.Adapters.Local](https://github.com/elixir-nebulex/nebulex_local):
  the local adapter, which implements all the optional behaviours (Info,
  Transaction, Observable). A good reference for optimizations.
- [nebulex_redis_adapter](https://github.com/elixir-nebulex/nebulex_redis_adapter/):
  an adapter for an external backend, with persistence and distributed
  operations.
- [Adapter API](`Nebulex.Adapter`): the reference for all adapter behaviours
  and callbacks (KV, CompositeKV, Queryable, Transaction, Info, and
  Observable).
