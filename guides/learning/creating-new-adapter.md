# Creating a new adapter

This guide will walk you through creating a custom Nebulex adapter. We will
start by creating a new project, making tests pass, and then implementing a
simple in-memory adapter. It will be roughly based on
[`Nebulex.Adapters.Redis`](https://github.com/elixir-nebulex/nebulex_redis_adapter/)
so you can consult this repo as an example.

## Mix Project

Nebulex's main repo contains some very useful shared tests that we are going to
take advantage of. To do so we will need to checkout Nebulex from GitHub as the
version published to Hex does not contain test code. To accommodate this
workflow we will start by creating a new project.

```console
mix new nebulex_memory_adapter
```

Now let's modify `mix.exs` so that we can fetch the Nebulex repository.

```elixir
defmodule NebulexMemoryAdapter.MixProject do
  use Mix.Project

  @nbx_vsn "3.0.0"
  @version "0.1.0"

  def project do
    [
      app: :nebulex_memory_adapter,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
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
      {:telemetry, "~> 0.4 or ~> 1.0", optional: true}
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

As you can see here we define a `mix nbx.setup` task that will fetch a Nebulex
version to a folder specified in the `NEBULEX_PATH` environment variable. Let's
run it.

```console
export NEBULEX_PATH=nebulex
mix nbx.setup
```

Now is a good time to fetch other dependencies.

```console
mix deps.get
```

## Tests

Before we start implementing our custom adapter, let's set up our tests.

First, it's important to understand which adapter behaviors we need to implement:

- **`Nebulex.Adapter.KV`** - Required. Provides key-value operations like `get`,
  `put`, `delete`, etc. All adapters must implement this.
- **`Nebulex.Adapter.Queryable`** - Optional. Provides query-based operations like
  `delete_all`, `get_all` with filters, etc. Recommended for most adapters.
- **`Nebulex.Adapter.Transaction`**, **`Nebulex.Adapter.Info`**,
  **`Nebulex.Adapter.Observable`** - Other optional behaviors for advanced features
  (documented separately in the Adapter API).

We'll implement `KV` and `Queryable` in this guide. Let's start by defining a
cache that uses our adapter in `test/support/test_cache.ex`

```elixir
defmodule NebulexMemoryAdapter.TestCache do
  use Nebulex.Cache,
    otp_app: :nebulex_memory_adapter,
    adapter: NebulexMemoryAdapter
end
```

We won't be writing tests ourselves. Instead, we'll use shared tests from the
Nebulex parent repo. To do so, we'll create a helper module in
`test/shared/cache_test.exs` that uses test suites for the behaviors we're
implementing. We'll test both `KV` and `Queryable` behaviors.

```elixir
defmodule NebulexMemoryAdapter.CacheTest do
  @moduledoc """
  Shared Tests
  """

  defmacro __using__(_opts) do
    quote do
      use Nebulex.Cache.KVTest
      use Nebulex.Cache.QueryableTest
    end
  end
end
```

Now let's edit `test/nebulex_memory_adapter_test.exs` to run the shared tests by
using `NebulexMemoryAdapter.CacheTest`. We also need to define a setup callback
that starts our cache process and puts the `cache` and `name` keys into the test
context.

```elixir
defmodule NebulexMemoryAdapterTest do
  use ExUnit.Case, async: true
  use NebulexMemoryAdapter.CacheTest

  alias NebulexMemoryAdapter.TestCache, as: Cache

  setup do
    pid = start_supervised!(Cache)
    _ignore = Cache.delete_all!()
    :ok

    {:ok, cache: Cache, name: Cache}
  end
end
```

Now let's run the tests to see what we need to implement.

```console
mix test
== Compilation error in file test/support/test_cache.ex ==
** (ArgumentError) expected :adapter option given to Nebulex.Cache to list Nebulex.Adapter as a behaviour
    (nebulex 2.4.2) lib/nebulex/cache/supervisor.ex:50: Nebulex.Cache.Supervisor.compile_config/1
    test/support/test_cache.ex:2: (module)
```

Looks like our adapter needs to implement the `Nebulex.Adapter` behaviour.
Luckily, it's just 2 callbacks that we can copy from `Nebulex.Adapters.Nil`

```elixir
# lib/nebulex_memory_adapter.ex
defmodule NebulexMemoryAdapter do
  @behaviour Nebulex.Adapter

  @impl Nebulex.Adapter
  defmacro __before_compile__(_env), do: :ok

  @impl Nebulex.Adapter
  def init(_opts) do
    child_spec = Supervisor.child_spec({Agent, fn -> :ok end}, id: {Agent, 1})
    {:ok, child_spec, %{}}
  end
end
```

Another try

```console
mix test
== Compilation error in file test/nebulex_memory_adapter_test.exs ==
** (CompileError) test/nebulex_memory_adapter_test.exs:3: module Nebulex.Cache.KVTest is not loaded and could not be found
    (elixir 1.13.2) expanding macro: Kernel.use/1
    test/nebulex_memory_adapter_test.exs:3: NebulexMemoryAdapterTest (module)
    expanding macro: NebulexMemoryAdapter.CacheTest.__using__/1
    test/nebulex_memory_adapter_test.exs:3: NebulexMemoryAdapterTest (module)
    (elixir 1.13.2) expanding macro: Kernel.use/1
    test/nebulex_memory_adapter_test.exs:3: NebulexMemoryAdapterTest (module)
```

The test files from the Nebulex parent repo aren't automatically compiled.
Let's address this in `test/test_helper.exs`

```elixir
# Nebulex dependency path
nbx_dep_path = Mix.Project.deps_paths()[:nebulex]

for file <- File.ls!("#{nbx_dep_path}/test/support"), file != "test_cache.ex" do
  Code.require_file("#{nbx_dep_path}/test/support/" <> file, __DIR__)
end

for file <- File.ls!("#{nbx_dep_path}/test/shared/cache") do
  Code.require_file("#{nbx_dep_path}/test/shared/cache/" <> file, __DIR__)
end

for file <- File.ls!("#{nbx_dep_path}/test/shared"), file != "cache" do
  Code.require_file("#{nbx_dep_path}/test/shared/" <> file, __DIR__)
end

# Load shared tests
for file <- File.ls!("test/shared"), not File.dir?("test/shared/" <> file) do
  Code.require_file("./shared/" <> file, __DIR__)
end

ExUnit.start()
```

One more attempt

```console
mix test
< ... >
 54) test put_all/2 puts the given entries using different data types at once (NebulexMemoryAdapterTest)
     test/nebulex_memory_adapter_test.exs:128
     ** (UndefinedFunctionError) function NebulexMemoryAdapter.TestCache.delete_all/0 is undefined or private. Did you mean:

           * delete/1
           * delete/2

     stacktrace:
       (nebulex_memory_adapter 0.1.0) NebulexMemoryAdapter.TestCache.delete_all()
       test/nebulex_memory_adapter_test.exs:9: NebulexMemoryAdapterTest.__ex_unit_setup_0/1
       test/nebulex_memory_adapter_test.exs:1: NebulexMemoryAdapterTest.__ex_unit__/2



Finished in 0.2 seconds (0.2s async, 0.00s sync)
54 tests, 54 failures
```

## Implementation

Now that we have our failing tests, we can implement the adapter. We'll build
this step-by-step, starting with the base `Nebulex.Adapter` behavior, then
implementing the required `Nebulex.Adapter.KV` behavior, and finally adding
the optional `Nebulex.Adapter.Queryable` behavior.

> **Note**: For a complete reference implementation with all the correct callback
> signatures and production patterns, consult the
> [Nebulex.TestAdapter](https://github.com/elixir-nebulex/nebulex/blob/main/test/support/test_adapter.exs)
> source code. This guide shows the essential structure and flow, but you'll want
> to refer to TestAdapter for exact implementations.

### Step 1: Implement Nebulex.Adapter

First, let's implement the base `Nebulex.Adapter` behavior with the two required
callbacks:

```elixir
defmodule NebulexMemoryAdapter do
  @behaviour Nebulex.Adapter

  import Nebulex.Utils

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
** (ArgumentError) expected :adapter option given to Nebulex.Cache to list Nebulex.Adapter.KV as a behaviour
    (nebulex 3.0.0) lib/nebulex/cache/supervisor.ex:50: Nebulex.Cache.Supervisor.compile_config/1
    test/support/test_cache.ex:2: (module)
```

The error tells us we need to implement `Nebulex.Adapter.KV`.

### Step 2: Implement Nebulex.Adapter.KV (Required)

The `Nebulex.Adapter.KV` behavior is the core requirement. It provides all
key-value operations like `fetch`, `put`, `delete`, and more. Here's a complete
implementation:

```elixir
defmodule NebulexMemoryAdapter do
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.KV

  import Nebulex.Utils

  @impl Nebulex.Adapter
  defmacro __before_compile__(_env), do: :ok

  @impl Nebulex.Adapter
  def init(_opts) do
    child_spec = Supervisor.child_spec({Agent, fn -> %{} end}, id: {Agent, 1})

    {:ok, child_spec, %{}}
  end

  ## Nebulex.Adapter.KV Implementation

  @impl Nebulex.Adapter.KV
  def fetch(adapter_meta, key, _opts) do
    wrap_ok Agent.get(adapter_meta.pid, &Map.get(&1, key))
  end

  @impl Nebulex.Adapter.KV
  def put(adapter_meta, key, value, on_write, ttl, _opts) do
    Agent.update(adapter_meta.pid, &Map.put(&1, key, value))
    {:ok, true}
  end

  @impl Nebulex.Adapter.KV
  def put_all(adapter_meta, entries, on_write, ttl, _opts) do
    entries = Map.new(entries)
    Agent.update(adapter_meta.pid, &Map.merge(&1, entries))
    {:ok, true}
  end

  @impl Nebulex.Adapter.KV
  def delete(adapter_meta, key, _opts) do
    wrap_ok Agent.update(adapter_meta.pid, &Map.delete(&1, key))
  end

  @impl Nebulex.Adapter.KV
  def take(adapter_meta, key, _opts) do
    value = Agent.get(adapter_meta.pid, &Map.get(&1, key))
    delete(adapter_meta, key, [])
    {:ok, value}
  end

  @impl Nebulex.Adapter.KV
  def update_counter(adapter_meta, key, amount, default, ttl, _opts) do
    Agent.update(adapter_meta.pid, fn state ->
      Map.update(state, key, default + amount, fn v -> v + amount end)
    end)

    wrap_ok Agent.get(adapter_meta.pid, &Map.get(&1, key))
  end

  @impl Nebulex.Adapter.KV
  def has_key?(adapter_meta, key, _opts) do
    wrap_ok Agent.get(adapter_meta.pid, &Map.has_key?(&1, key))
  end

  @impl Nebulex.Adapter.KV
  def ttl(_adapter_meta, _key, _opts) do
    {:ok, nil}
  end

  @impl Nebulex.Adapter.KV
  def expire(_adapter_meta, _key, _ttl, _opts) do
    {:ok, true}
  end

  @impl Nebulex.Adapter.KV
  def touch(_adapter_meta, _key, _opts) do
    {:ok, true}
  end
end
```

Running the tests again:

```console
mix test
< ... >

 10) test delete_all/2 deletes all entries (NebulexMemoryAdapterTest)
     test/nebulex_memory_adapter_test.exs:128
     ** (UndefinedFunctionError) function NebulexMemoryAdapter.execute/3 is undefined or private
     stacktrace:
       (nebulex_memory_adapter 0.1.0) NebulexMemoryAdapter.execute(%{cache: NebulexMemoryAdapter.TestCache, pid: #PID<0.549.0>}, %{op: :delete_all, query: {:q, nil}}, [])
       test/nebulex_memory_adapter_test.exs:129: (test)



Finished in 5.7 seconds (5.7s async, 0.00s sync)
54 tests, 10 failures
```

Great progress! We've gone from 54 failures to 10. The remaining failures are for
the `execute/3` function, which is part of the `Nebulex.Adapter.Queryable` behavior.

### Step 3: Add Nebulex.Adapter.Queryable (Optional)

Now we'll add the optional `Nebulex.Adapter.Queryable` behavior to support
query operations like `delete_all`, `get_all`, and `stream`. Here's the complete
implementation of both `KV` and `Queryable` that passes all tests:

```elixir
defmodule NebulexMemoryAdapter do
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.KV
  @behaviour Nebulex.Adapter.Queryable

  import Nebulex.Utils

  @impl Nebulex.Adapter
  defmacro __before_compile__(_env), do: :ok

  @impl Nebulex.Adapter
  def init(_opts) do
    child_spec = Supervisor.child_spec({Agent, fn -> %{} end}, id: {Agent, 1})

    {:ok, child_spec, %{}}
  end

  @impl Nebulex.Adapter.KV
  def fetch(adapter_meta, key, _opts) do
    wrap_ok Agent.get(adapter_meta.pid, &Map.get(&1, key))
  end

  @impl Nebulex.Adapter.KV
  def put(adapter_meta, key, value, ttl, op, opts)

  def put(adapter_meta, key, value, ttl, :put_new, opts) do
    if get(adapter_meta, key, []) do
      false
    else
      put(adapter_meta, key, value, ttl, :put, opts)
      true
    end
    |> wrap_ok()
  end

  def put(adapter_meta, key, value, ttl, :replace, opts) do
    if get(adapter_meta, key, []) do
      put(adapter_meta, key, value, ttl, :put, opts)

      true
    else
      false
    end
    |> wrap_ok()
  end

  def put(adapter_meta, key, value, _ttl, _on_write, _opts) do
    Agent.update(adapter_meta.pid, &Map.put(&1, key, value))

    {:ok, true}
  end

  @impl Nebulex.Adapter.KV
  def put_all(adapter_meta, entries, ttl, op, opts)

  def put_all(adapter_meta, entries, ttl, :put_new, opts) do
    if get_all(adapter_meta, Map.keys(entries), []) == %{} do
      put_all(adapter_meta, entries, ttl, :put, opts)

      true
    else
      false
    end
    |> wrap_ok()
  end

  def put_all(adapter_meta, entries, _ttl, _on_write, _opts) do
    entries = Map.new(entries)

    Agent.update(adapter_meta.pid, &Map.merge(&1, entries))

    {:ok, true}
  end

  @impl Nebulex.Adapter.KV
  def delete(adapter_meta, key, _opts) do
    wrap_ok Agent.update(adapter_meta.pid, &Map.delete(&1, key))
  end

  @impl Nebulex.Adapter.KV
  def take(adapter_meta, key, _opts) do
    value = get(adapter_meta, key, [])

    delete(adapter_meta, key, [])

    {:ok, value}
  end

  @impl Nebulex.Adapter.KV
  def update_counter(adapter_meta, key, amount, _ttl, default, _opts) do
    Agent.update(adapter_meta.pid, fn state ->
      Map.update(state, key, default + amount, fn v -> v + amount end)
    end)

    wrap_ok get(adapter_meta, key, [])
  end

  @impl Nebulex.Adapter.KV
  def has_key?(adapter_meta, key, _opts) do
    wrap_ok Agent.get(adapter_meta.pid, &Map.has_key?(&1, key))
  end

  @impl Nebulex.Adapter.KV
  def ttl(_adapter_meta, _key, _opts) do
    {:ok, nil}
  end

  @impl Nebulex.Adapter.KV
  def expire(_adapter_meta, _key, _ttl, _opts) do
    {:ok, true}
  end

  @impl Nebulex.Adapter.KV
  def touch(_adapter_meta, _key, _opts) do
    {:ok, true}
  end

  @impl Nebulex.Adapter.Queryable
  def execute(adapter_meta, query_meta, _opts) do
    do_execute(adapter_meta.pid, query_meta)
  end

  def do_execute(pid, %{op: :delete_all} = query_meta) do
    deleted = do_execute(pid, %{query_meta | op: :count_all})

    Agent.update(pid, fn _state -> %{} end)

    {:ok, deleted}
  end

  def do_execute(pid, %{op: :count_all}) do
    wrap_ok Agent.get(pid, &map_size/1)
  end

  def do_execute(pid, %{op: :get_all, query: {:q, nil}}) do
    wrap_ok Agent.get(pid, &Map.values/1)
  end

  # Fetching multiple keys
  def do_execute(pid, %{op: :get_all, query: {:in, keys}}) do
    pid
    |> Agent.get(&Map.take(&1, keys))
    |> Map.to_list()
    |> wrap_ok()
  end

  @impl Nebulex.Adapter.Queryable
  def stream(adapter_meta, query_meta, _opts) do
    do_stream(adapter_meta.pid, query_meta)
  end

  def do_stream(pid, %{query: {:q, q}, select: select}) when q in [nil, :all] do
    fun =
      case select do
        :value ->
          &Map.values/1

        {:key, :value} ->
          &Map.to_list/1

        _ ->
          &Map.keys/1
      end

    wrap_ok Agent.get(pid, fun)
  end

  def do_stream(_pid_, query) do
    wrap_error Nebulex.QueryError, query: query
  end
end
```

Of course, this isn't a useful adapter for production use, but it demonstrates
the minimum implementation needed to get both KV and Queryable behaviors working.
This should give you a solid foundation for building your own adapter.

## Next Steps

Now that you have a working adapter, you can:

1. **Expand the KV behavior** - Implement additional callbacks like `expire/4` and
   `touch/3` if your adapter supports TTL.
2. **Add more Queryable operations** - Implement more query operations to support
   filtering, sorting, and other advanced features.
3. **Add optional behaviors** - Implement `Transaction`, `Info`, or `Observable`
   behaviors as needed (consult the Adapter API documentation).
4. **Optimize for your backend** - Replace the simple `Agent` storage with actual
   backend calls (Redis, Memcached, database, etc.).
5. **Add comprehensive tests** - Write tests specific to your adapter beyond the
   shared Nebulex tests.

## Recommended Reading

- **[Nebulex.TestAdapter](https://github.com/elixir-nebulex/nebulex/blob/main/test/support/test_adapter.exs)**
  - The canonical reference implementation used by Nebulex itself for testing
  - Shows correct callback signatures and implementations for KV and Queryable
  - Reference for handling TTL, entry validation, and error cases
  - Best for understanding exact callback parameters and return values

- **[Nebulex.Adapters.Local](https://github.com/elixir-nebulex/nebulex/blob/main/lib/nebulex/adapters/local)**
  - Built-in adapter implementation with all optional behaviors
  - Shows advanced features like Info API, Transaction support, and Observable
  - Reference for optimizations and production-ready patterns

- **[nebulex_redis_adapter](https://github.com/elixir-nebulex/nebulex_redis_adapter/)**
  - Real-world example of a distributed cache adapter
  - Shows how to integrate with an external backend
  - Reference for handling complex operations with actual persistence

- **[Adapter Behavior Documentation](`Nebulex.Adapter`)**
  - Complete API reference for all adapter behaviors and callbacks
  - Detailed specifications for KV, Queryable, Transaction, Info, and Observable
