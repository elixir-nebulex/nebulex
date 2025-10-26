# Getting Started

This guide introduces [Nebulex][nbx_repo], a local and distributed
caching toolkit for Elixir. The Nebulex API is heavily inspired by
[Ecto](https://github.com/elixir-ecto/ecto), leveraging its simplicity,
flexibility, and pluggable architecture. Like Ecto, developers can provide
their own cache (adapter) implementations. In this guide, we'll learn
the basics of Nebulex, including how to write, read, and delete cache entries.

[nbx_repo]: https://github.com/elixir-nebulex/nebulex

---

## Adding Nebulex to Your Application

Let's start by creating a new Elixir application:

```bash
mix new blog --sup
```

The `--sup` option ensures that this application has
[a supervision tree](https://hexdocs.pm/elixir/supervisor-and-application.html),
which will be needed by Nebulex later on.

To add Nebulex to your application, follow these steps:

### Step 1: Add Dependencies

Add both Nebulex and the cache adapter as dependencies
to your `mix.exs` file by updating the `deps` definition:

```elixir
defp deps do
  [
    {:nebulex, "~> 3.0"},
    # Use the official local cache adapter
    {:nebulex_local, "~> 3.0"},
    # Required for caching decorators (recommended)
    {:decorator, "~> 1.4"},
    # Required for telemetry events (recommended)
    {:telemetry, "~> 1.0"},
    # Required for :shards backend in local adapter
    {:shards, "~> 1.1"}
  ]
end
```

To provide more flexibility and load only the needed dependencies, Nebulex makes
all dependencies optional, including the adapters. For example:

  * **For enabling [declarative decorator-based caching][nbx_caching]**:
    Add `:decorator` to the dependency list.

  * **For enabling Telemetry events**: Add `:telemetry` to the dependency list.
    See the [Info API guide](http://hexdocs.pm/nebulex/3.0.0-rc.2/info-api.html)
    for monitoring cache stats and metrics.

  * **For intensive workloads** when using `Nebulex.Adapters.Local` adapter:
    You may want to use `:shards` as the backend for partitioned ETS tables.
    In such cases, add `:shards` to the dependency list.

[nbx_caching]: http://hexdocs.pm/nebulex/3.0.0-rc.2/Nebulex.Caching.html

Install these dependencies by running:

```bash
mix deps.get
```

### Step 2: Generate Cache Configuration

We now need to define a Cache and set up some configuration for Nebulex so that
we can perform actions on a cache from within the application's code.

Generate the required configuration by running:

```bash
mix nbx.gen.cache -c Blog.Cache
```

This command will generate the configuration required to use the cache. The
first bit of configuration is in `config/config.exs`:

```elixir
config :blog, Blog.Cache,
  # Sets :shards as backend (defaults to :ets)
  # backend: :shards,
  # GC interval for pushing a new generation (e.g., 12 hrs)
  gc_interval: :timer.hours(12),
  # Max number of entries (e.g., 1 million)
  max_size: 1_000_000,
  # Max memory size in bytes (e.g., 2GB)
  allocated_memory: 2_000_000_000,
  # GC interval for checking memory and maybe evict entries (e.g., 10 sec)
  gc_memory_check_interval: :timer.seconds(10)
```

If you want to use `:shards` as the backend, uncomment the `backend:` option.

> See the adapter documentation for more information.

The `Blog.Cache` module is defined in `lib/blog/cache.ex` by our
`mix nbx.gen.cache` command:

```elixir
defmodule Blog.Cache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Local
end
```

This module is what we'll use to interact with the cache. It uses the
`Nebulex.Cache` module and expects the `:otp_app` option. The `otp_app`
tells Nebulex which Elixir application to look for cache configuration in.
In this case, we've specified that it is the `:blog` application where Nebulex
can find that configuration, so Nebulex will use the configuration that was
set up in `config/config.exs`.

### Step 3: Add to Supervision Tree

The final piece of configuration is to set up the `Blog.Cache` as a
supervisor within the application's supervision tree. We can do this in
`lib/blog/application.ex`, inside the `start/2` function:

```elixir
def start(_type, _args) do
  children = [
    Blog.Cache
  ]

  # ... rest of your supervision tree
```

This configuration will start the Nebulex process which receives and executes
our application's commands. Without it, we wouldn't be able to use the cache
at all!

We've now configured our application so that it's able to execute commands
against our cache.

> **⚠️ Important:** Make sure the cache is placed first in the children
> list, or at least before the processes that use it. Otherwise, there
> could be race conditions causing exceptions; processes attempting to use
> the cache before it has even started.

---

## Inserting Entries

We can insert new entries into our blog cache with this code:

```elixir
iex> user = %{id: 1, first_name: "Galileo", last_name: "Galilei"}
iex> Blog.Cache.put(user[:id], user, ttl: :timer.hours(1))
:ok
```

To insert data into our cache, we call `put` on `Blog.Cache`. This function
tells Nebulex that we want to insert a new key/value entry into the cache
corresponding to `Blog.Cache`.

It's also possible to insert multiple entries at once:

```elixir
iex> users = %{
...>   1 => %{id: 1, first_name: "Galileo", last_name: "Galilei"},
...>   2 => %{id: 2, first_name: "Charles", last_name: "Darwin"},
...>   3 => %{id: 3, first_name: "Albert", last_name: "Einstein"}
...> }
iex> Blog.Cache.put_all(users)
:ok
```

> The given entries can be a `map` or a key/value tuple list.

### Inserting New Entries vs. Replacing Existing Ones

As we saw previously, `put` creates a new entry in the cache if it doesn't
exist, or overrides it if it does exist (including the `:ttl`). However, there
might be circumstances where we want to set the entry only if it doesn't exist,
or the other way around. For those cases, you can use `put_new` and `replace`
functions instead.

Let's try the `put_new` and `put_new!` functions:

```elixir
iex> new_user = %{id: 4, first_name: "John", last_name: "Doe"}
iex> Blog.Cache.put_new(new_user.id, new_user, ttl: 900)
{:ok, true}

iex> Blog.Cache.put_new(new_user.id, new_user)
{:ok, false}

# Same as the previous one but raises `Nebulex.Error` in case of error
iex> Blog.Cache.put_new!(new_user.id, new_user)
false
```

Now let's try the `replace` and `replace!` functions:

```elixir
iex> existing_user = %{id: 5, first_name: "John", last_name: "Doe2"}
iex> Blog.Cache.replace(existing_user.id, existing_user)
{:ok, false}

iex> Blog.Cache.put_new(existing_user.id, existing_user)
{:ok, true}

iex> Blog.Cache.replace(existing_user.id, existing_user, ttl: 900)
{:ok, true}

# same as previous one but raises `Nebulex.Error` in case of error
iex> Blog.Cache.replace!(existing_user.id, existing_user)
true

iex> Blog.Cache.replace!("unknown", existing_user)
false
```

It is also possible to insert multiple new entries at once:

```elixir
iex> new_users = %{
...>   6 => %{id: 6, first_name: "Isaac", last_name: "Newton"},
...>   7 => %{id: 7, first_name: "Marie", last_name: "Curie"}
...> }
iex> Blog.Cache.put_new_all(new_users)
{:ok, true}

# none of the entries is inserted if at least one key already exists
iex> Blog.Cache.put_new_all(new_users)
{:ok, false}

# same as previous one but raises `Nebulex.Error` in case of error
iex> Blog.Cache.put_new_all!(new_users)
false
```

## Retrieving entries

Let's start off with fetching data by the key, which is the most basic and
common operation to retrieve data from a cache.

```elixir
# Using `fetch` callback
iex> {:ok, user1} = Blog.Cache.fetch(1)
iex> user1.id
1

# If the key doesn't exist an error tuple is returned
iex> {:error, %Nebulex.KeyError{} = e} = Blog.Cache.fetch("unknown")
iex> e.key
"unknown"

# Using `fetch!` (same as `fetch` but raises an exception in case of error)
iex> user1 = Blog.Cache.fetch!(1)
iex> user1.id
1

# Using `get` callback (returns the default in case the key doesn't exist)
iex> {:ok, user1} = Blog.Cache.get(1)
iex> user1.id
1

# Returns the default because the key doesn't exist
iex> Blog.Cache.get("unknown")
{:ok, nil}
iex> Blog.Cache.get("unknown", "default")
{:ok, "default"}

# Using `get!` (same as `get` but raises an exception in case of error)
iex> user1 = Blog.Cache.get!(1)
iex> user1.id
1
iex> Blog.Cache.get!("unknown")
nil
iex> Blog.Cache.get!("unknown", "default")
"default"

iex> Enum.map(1..3, &(Blog.Cache.get!(&1).first_name))
["Galileo", "Charles", "Albert"]
```

There is a function `has_key?` to check if a key exist in cache:

```elixir
iex> Blog.Cache.has_key?(1)
{:ok, true}

iex> Blog.Cache.has_key?(10)
{:ok, false}
```

## Updating entries

Nebulex provides `update` and `get_and_update` functions to update an
entry value based on current one, for example:

```elixir
iex> initial = %{id: 1, first_name: "", last_name: ""}

# using `get_and_update`
iex> Blog.Cache.get_and_update(1, fn v ->
...>   if v, do: {v, %{v | first_name: "X"}}, else: {v, initial}
...> end)
{:ok, {_old, _updated}}

# using `update`
iex> Blog.Cache.update(1, initial, &(%{&1 | first_name: "Y"}))
{:ok, _updated}
```

> You can also use the version with the trailing bang (`!`) `get_and_update!`
> and `!update`.

## Fetch or Store and Get or Store

Nebulex provides two powerful functions for lazy loading and caching:
`fetch_or_store` and `get_or_store`. These functions are particularly useful in\
scenarios where you want to:

- **Lazy load data**: Only fetch data from an external source when it's actually
  requested.
- **Cache expensive operations**: Store the result of database queries, API
  calls, or complex computations.
- **Implement cache-aside pattern**: Check the cache first, then fall back to
  the data source if needed.
- **Avoid cache stampede**: Prevent multiple concurrent requests from hitting
  the same expensive operation.

The key difference between these functions is how they handle the return value
from the provided function:

- `fetch_or_store` expects the function to return `{:ok, value}` or
  `{:error, reason}` and only caches successful results.
- `get_or_store` always caches whatever the function returns, including error
  tuples.

### Fetch or Store

Use `fetch_or_store` when you want to cache only successful results and handle
errors separately:

```elixir
# Cache successful API responses, but don't cache errors
iex> Blog.Cache.fetch_or_store("user:123", fn ->
...>   case fetch_user_from_api(123) do
...>     {:ok, user} -> {:ok, user}
...>     {:error, reason} -> {:error, reason}
...>   end
...> end)
{:ok, %{id: 123, name: "John Doe"}}

# If the function returns an error, it won't be cached
iex> Blog.Cache.fetch_or_store("user:999", fn ->
...>   {:error, "User not found"}
...> end)
{:error, %Nebulex.Error{reason: "User not found"}}

# Subsequent calls will still execute the function since errors aren't cached
iex> Blog.Cache.fetch_or_store("user:999", fn ->
...>   {:error, "User not found"}
...> end)
{:error, %Nebulex.Error{reason: "User not found"}}
```

### Get or Store

Use `get_or_store` when you want to cache everything, including error responses:

```elixir
# Cache API responses regardless of success or failure
iex> Blog.Cache.get_or_store("api:users", fn ->
...>   fetch_users_from_api()
...> end)
{:ok, %{users: [%{id: 1, name: "John"}]}}

# Even error responses get cached
iex> Blog.Cache.get_or_store("api:invalid", fn ->
...>   {:error, "Rate limited"}
...> end)
{:ok, {:error, "Rate limited"}}

# Subsequent calls return the cached error without hitting the API
iex> Blog.Cache.get_or_store("api:invalid", fn ->
...>   {:error, "Rate limited"}
...> end)
{:ok, {:error, "Rate limited"}}
```

### When to Use Each

- **Use `fetch_or_store`** when:
  - You want to cache only successful results
  - You need to handle errors differently (e.g., retry logic)
  - You're implementing a cache-aside pattern for external APIs
  - You want to avoid caching transient failures

- **Use `get_or_store`** when:
  - You want to cache everything (success and errors)
  - You're implementing rate limiting or circuit breaker patterns
  - You want to avoid repeated expensive operations even when they fail
  - You're caching database query results

> **Note**: Both functions are not atomic operations. They use `fetch` and `put`
> under the hood, but the function execution happens outside the cache
> transaction. If you need atomicity, consider wrapping the operation
> in a `transaction/2` call.

## Counters

The function `incr` is provided to increment or decrement a counter; by default,
a counter is initialized to `0`. Let's see how counters works:

```elixir
# by default, the counter is incremented by 1
iex> Blog.Cache.incr(:my_counter)
{:ok, 1}

# but we can also provide a custom increment value
iex> Blog.Cache.incr(:my_counter, 5)
{:ok, 6}

# to decrement the counter, just pass a negative value
iex> Blog.Cache.incr(:my_counter, -5)
{:ok, 1}

# using `incr!`
iex> Blog.Cache.incr!(:my_counter)
2
```

## Deleting entries

We've now covered inserting, reading and updating entries. Now let's see how to
delete an entry using Nebulex.

```elixir
iex> Blog.Cache.delete(1)
:ok

# or `delete!`
iex> Blog.Cache.delete!(1)
:ok
```

### Take

This is another way not only for deleting an entry but also for retrieving it
before its delete it:

```elixir
iex> Blog.Cache.take(1)
{:ok, _entry}

# If the key doesn't exist an error tuple is returned
iex> {:error, %Nebulex.KeyError{} = e} = Blog.Cache.take("nonexistent")
iex> e.key
"nonexistent"

# same as previous one but raises `Nebulex.KeyError`
iex> Blog.Cache.take!("nonexistent")
```

## Entry expiration

You can get the remaining TTL or expiration time for a key like so:

```elixir
# If no TTL is set when the entry is created, `:infinity` is set by default
iex> Blog.Cache.ttl(1)
{:ok, :infinity}

# If the key doesn't exist an error tuple is returned
iex> {:error, %Nebulex.KeyError{} = e} = Blog.Cache.ttl("nonexistent")
iex> e.key
"nonexistent"

# Same as `ttl` but an exception is raised if an error occurs
iex> Blog.Cache.ttl!(1)
:infinity
```

You could also change or update the expiration time using `expire`, like so:

```elixir
iex> Blog.Cache.expire(1, :timer.hours(1))
{:ok, true}

# When the key doesn't exist false is returned
iex> Blog.Cache.expire("nonexistent", :timer.hours(1))
{:ok, false}

# Same as `expire` but an exception is raised if an error occurs
iex> Blog.Cache.expire!(1, :timer.hours(1))
true
```

## Query and/or Stream entries

Nebulex provides functions to fetch, count, delete, or stream all entries from
cache matching the given query.

### Fetch all entries from cache matching the given query

```elixir
# by default, returns all entries
iex> Blog.Cache.get_all() #=> The query is set to nil by default
{:ok, _all_entries}

# fetch all entries and return the keys
iex> Blog.Cache.get_all(select: :key)
{:ok, _all_keys}

# fetch all entries and return the values
iex> Blog.Cache.get_all(select: :value)
{:ok, _all_values}

# fetch entries associated to the requested keys
iex> Blog.Cache.get_all(in: [1, 2])
{:ok, _fetched_entries}

# raises an exception in case of error
iex> Blog.Cache.get_all!()
_all_entries

# raises an exception in case of error
iex> Blog.Cache.get_all!(in: [1, 2])
_fetched_entries

# built-in queries in `Nebulex.Adapters.Local` adapter
iex> Blog.Cache.get_all() #=> Equivalent to Blog.Cache.get_all(query: nil)

# if we are using `Nebulex.Adapters.Local` adapter, the stored entry
# is a tuple `{:entry, key, value, touched, ttl}`, then the match spec
# could be something like:
iex> spec = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$1", 10}], [{{:"$1", :"$2"}}]}]
iex> Blog.Cache.get_all(query: spec)
{:ok, _all_matched}

# using Ex2ms
iex> import Ex2ms
iex> spec =
...>   fun do
...>     {_, key, value, _, _} when key > 10 -> {key, value}
...>   end
iex> Blog.Cache.get_all(query: spec)
{:ok, _all_matched}
```

### Count all entries from cache matching the given query

For example, to get the total number of cached objects (cache size):

```elixir
# by default, counts all entries
iex> Blog.Cache.count_all() #=> The query is set to nil by default
{:ok, _num_cached_entries}

# raises an exception in case of error
iex> Blog.Cache.count_all!()
_num_cached_entries
```

Similar to `get_all`, you can pass a query to count only the matched entries.
For example, `Blog.Cache.count_all(query: query)`.

### Delete all entries from cache matching the given query

Similar to `count_all/2`, Nebulex provides `delete_all/2` to not only count
the matched entries but also remove them from the cache at once, in one single
execution.

The first example is flushing the cache, delete all cached entries (which is
the default behavior when none query is provided):

```elixir
iex> Blog.Cache.delete_all()
{:ok, _num_of_removed_entries}

# raises an exception in case of error
iex> Blog.Cache.delete_all!()
_num_of_removed_entries
```

One may also delete a list of keys at once (like a bulk delete):

```elixir
iex> Blog.Cache.delete_all(in: ["k1", "k2"])
{:ok, _num_of_removed_entries}

# raises an exception in case of error
iex> Blog.Cache.delete_all!(in: ["k1", "k2"])
_num_of_removed_entries
```

### Stream all entries from cache matching the given query

Similar to `get_all` but returns a lazy enumerable that emits all entries from
the cache matching the provided query.

If the query is `nil`, then all entries in cache match and are returned when the
stream is evaluated (based on the `:select` option).

```elixir
iex> {:ok, stream} = Blog.Cache.stream()
iex> Enum.to_list(stream)
_all_matched

iex> {:ok, stream} = Blog.Cache.stream(select: :key)
iex> Enum.to_list(stream)
_all_matched

iex> {:ok, stream} = Blog.Cache.stream([select: :value], max_entries: 100)
iex> Enum.to_list(stream)
_all_matched

# raises an exception in case of error
iex> stream = Blog.Cache.stream!()
iex> Enum.to_list(stream)
_all_matched

# using `Nebulex.Adapters.Local` adapter
iex> spec = [{{:entry, :"$1", :"$2", :_, :_}, [{:<, :"$1", 3}], [{{:"$1", :"$2"}}]}]
iex> {:ok, stream} = Blog.Cache.stream(query: spec)
iex> Enum.to_list(stream)
_all_matched

# using Ex2ms
iex> import Ex2ms
iex> spec =
...>   fun do
...>     {:entry, key, value, _, _} when key < 3 -> {key, value}
...>   end
iex> {:ok, stream} = Blog.Cache.stream(query: spec)
iex> Enum.to_list(stream)
_all_matched
```

## Cache Info API

Since Nebulex v3, there is a new API for getting information about the cache
(including stats).

Although Nebulex suggests the adapters add information items like `:server`,
`:memory`, and `:stats`, the adapters are free to add the information
specification keys they want. Therefore, it is important to check the adapter
documentation. For this example, we use the official local adapter that supports
the suggested items.

```elixir
# Returns all information items
iex> {:ok, info} = Blog.Cache.info()
iex> info
%{
  server: %{
    nbx_version: "3.0.0",
    cache_module: "Blog.Cache",
    cache_adapter: "Nebulex.Adapters.Local",
    cache_name: "Blog.Cache",
    cache_pid: #PID<0.111.0>
  },
  memory: %{
    total: 1_000_000,
    used: 0
  },
  stats: %{
    deletions: 0,
    evictions: 0,
    expirations: 0,
    hits: 0,
    misses: 0,
    updates: 0,
    writes: 0
  }
}

# Returns a single item
iex> Blog.Cache.info!(:server)
%{
  nbx_version: "3.0.0",
  cache_module: "Blog.Cache",
  cache_adapter: "Nebulex.Adapters.Local",
  cache_name: "Blog.Cache",
  cache_pid: #PID<0.111.0>
}

# Returns the given items
iex> Blog.Cache.info!([:server, :stats])
%{
  server: %{
    nbx_version: "3.0.0",
    cache_module: "Blog.Cache",
    cache_adapter: "Nebulex.Adapters.Local",
    cache_name: "Blog.Cache",
    cache_pid: #PID<0.111.0>
  },
  stats: %{
    deletions: 0,
    evictions: 0,
    expirations: 0,
    hits: 0,
    misses: 0,
    updates: 0,
    writes: 0
  }
}
```

## Cache events

Since Nebulex v3, a powerful event system is available for monitoring cache
operations. You can register event listeners that are invoked after cache
entries are mutated, enabling you to build sophisticated monitoring, logging,
and analytics systems.

### Basic Event Handling

The simplest way to handle cache events is to register a listener function:

```elixir
defmodule Blog.Cache.EventHandler do
  def handle(event) do
    IO.inspect(event, label: "Cache Event")
  end
end

# Register the event listener
iex> Blog.Cache.register_event_listener(&Blog.Cache.EventHandler.handle/1)
:ok

# Now perform some cache operations to see events
iex> Blog.Cache.put("user:123", %{id: 123, name: "John Doe"})
:ok

#=> Cache Event: %Nebulex.Event.CacheEntryEvent{
#=>   cache: Blog.Cache,
#=>   name: Blog.Cache,
#=>   type: :inserted,
#=>   target: {:key, "user:123"},
#=>   command: :put,
#=>   metadata: []
#=> }

iex> Blog.Cache.replace("user:123", %{id: 123, name: "John Doe", email: "john@example.com"})
{:ok, %{id: 123, name: "John Doe", email: "john@example.com"}}

#=> Cache Event: %Nebulex.Event.CacheEntryEvent{
#=>   cache: Blog.Cache,
#=>   type: :updated,
#=>   target: {:key, "user:123"},
#=>   command: :replace,
#=>   metadata: []
#=> }

iex> Blog.Cache.delete("user:123")
:ok

#=> Cache Event: %Nebulex.Event.CacheEntryEvent{
#=>   cache: Blog.Cache,
#=>   type: :deleted,
#=>   target: {:key, "user:123"},
#=>   command: :delete,
#=>   metadata: []
#=> }
```

### Event Types and Commands

Cache events are triggered by different operations and have specific types:

- **`:inserted`** - When entries are added via `put`, `put_new`, `put_all`,
  or `put_new_all`.
- **`:updated`** - When existing entries are modified via `replace`, `expire`,
  or `touch`.
- **`:deleted`** - When entries are removed via `delete` or `delete_all`.
- **`:expired`** - When entries are evicted due to TTL expiration.

### Advanced Event Handling with Filters

You can use filters to only receive events for specific operations or
conditions. Filters are functions that return `true` to process an event
or `false` to ignore it. This approach is more efficient than filtering
in the handler function because:

- **Performance**: Events are filtered before reaching your handler, reducing
  unnecessary function calls.
- **Clarity**: Handler functions can focus on processing logic rather than
  filtering logic.
- **Reusability**: Filter functions can be shared between different handlers.
- **Composability**: You can create complex filtering logic by combining
  multiple filter functions.

```elixir
defmodule Blog.Cache.AnalyticsHandler do
  def handle_insertions(event) do
    # Only handle insertions (filter ensures this is always :inserted)
    %{target: {:key, key}} = event
    IO.puts("New cache entry: #{key}")
    # Send metrics to your analytics system
    # increment_counter("cache.insertions")
  end

  def handle_user_events(event) do
    # Only handle events for user-related keys (filter ensures this is always a user key)
    %{target: {:key, key}, type: type} = event
    IO.puts("User cache event: #{type} for #{key}")
  end

  # Filter functions - return true to process the event, false to ignore it
  def filter_insertions(%{type: :inserted}), do: true
  def filter_insertions(_other), do: false

  def filter_user_keys(%{target: {:key, "user:" <> _ = key}}), do: true
  def filter_user_keys(_other), do: false

  def filter_specific_commands(%{command: command}) when command in [:put, :put_new], do: true
  def filter_specific_commands(_other), do: false
end

# Register listeners with specific filters
iex> Blog.Cache.register_event_listener(
...>   &Blog.Cache.AnalyticsHandler.handle_insertions/1,
...>   id: :insertion_tracker,
...>   filter: &Blog.Cache.AnalyticsHandler.filter_insertions/1
...> )
:ok

iex> Blog.Cache.register_event_listener(
...>   &Blog.Cache.AnalyticsHandler.handle_user_events/1,
...>   id: :user_tracker,
...>   filter: &Blog.Cache.AnalyticsHandler.filter_user_keys/1
...> )
:ok

# You can also combine filters for more specific event handling
iex> Blog.Cache.register_event_listener(
...>   &Blog.Cache.AnalyticsHandler.handle_insertions/1,
...>   id: :put_operations,
...>   filter: &Blog.Cache.AnalyticsHandler.filter_specific_commands/1
...> )
:ok

# Now only relevant events will be processed
iex> Blog.Cache.put("user:456", %{id: 456, name: "Jane Smith"})
:ok
#=> New cache entry: user:456
#=> User cache event: inserted for user:456

iex> Blog.Cache.put("config:theme", "dark")
:ok
#=> New cache entry: config:theme
# (no user event since the filter excludes non-user keys)

iex> Blog.Cache.replace("user:456", %{id: 456, name: "Jane Smith", email: "jane@example.com"})
{:ok, %{id: 456, name: "Jane Smith", email: "jane@example.com"}}
#=> User cache event: updated for user:456
# (no insertion event since replace doesn't trigger :inserted type)
```

### Event Metadata and Context

You can attach custom metadata to your event listeners for additional context:

```elixir
defmodule Blog.Cache.MonitoringHandler do
  def handle_with_context(%{metadata: metadata} = event) do
    case metadata do
      [environment: env, service: service] ->
        IO.puts("[#{env}] #{service}: #{event.type} event for #{inspect(event.target)}")

      [level: level] ->
        # Different handling based on monitoring level
        case level do
          :debug -> IO.inspect(event, label: "DEBUG")
          :info -> IO.puts("Cache #{event.type}: #{inspect(event.target)}")
          :warn -> IO.puts("WARNING: Cache #{event.type} event")
        end

      _ ->
        IO.puts("Cache event: #{event.type}")
    end
  end
end

# Register with different metadata configurations
iex> Blog.Cache.register_event_listener(
...>   &Blog.Cache.MonitoringHandler.handle_with_context/1,
...>   id: :production_monitor,
...>   metadata: [environment: :production, service: :blog_api]
...> )
:ok

iex> Blog.Cache.register_event_listener(
...>   &Blog.Cache.MonitoringHandler.handle_with_context/1,
...>   id: :debug_monitor,
...>   metadata: [level: :debug]
...> )
:ok

# Events now include the metadata
iex> Blog.Cache.put("post:789", %{title: "Hello World"})
:ok
#=> [production] blog_api: inserted event for {:key, "post:789"}
#=> DEBUG: %Nebulex.Event.CacheEntryEvent{...}
```

### Managing Event Listeners

You can register multiple listeners and manage them individually:

```elixir
# Register with custom IDs for easier management
iex> Blog.Cache.register_event_listener(
...>   &Blog.Cache.EventHandler.handle/1,
...>   id: :general_logger
...> )
{:ok, :general_logger}

iex> Blog.Cache.register_event_listener(
...>   &Blog.Cache.AnalyticsHandler.handle_insertions/1,
...>   id: :analytics
...> )
{:ok, :analytics}

# Unregister specific listeners
iex> Blog.Cache.unregister_event_listener(:general_logger)
:ok

iex> Blog.Cache.unregister_event_listener(:analytics)
:ok
```

### Performance Considerations

Event listeners are executed synchronously and can impact cache operation
performance. Keep your event handlers lightweight:

```elixir
defmodule Blog.Cache.FastEventHandler do
  def handle(event) do
    # Send to a separate process for heavy processing
    spawn(fn -> process_event_async(event) end)

    # Or use GenServer for queuing
    # Blog.Cache.EventProcessor.cast(event)

    :ok
  end

  defp process_event_async(event) do
    # Heavy processing here (database writes, external API calls, etc.)
    :timer.sleep(100) # Simulate heavy work
    IO.puts("Processed event: #{event.type}")
  end
end
```

> **Note**: Event listeners are fired after the cache operation completes,
> so they don't affect the success or failure of the cache operation itself.
> They're perfect for monitoring, analytics, and side effects that shouldn't
> interfere with cache performance.

## Distributed cache topologies

### Partitioned Cache

Nebulex provides the adapter `Nebulex.Adapters.Partitioned`, which allows to
set up a partitioned cache topology. First of all, we need to add
`:nebulex_distributed` to the dependencies in the `mix.exs`:

```elixir
defp deps do
  [
    {:nebulex, "~> 3.0"},
    # Use the official local cache adapter
    {:nebulex_local, "~> 3.0"},
    # Use the official distributed cache adapters
    {:nebulex_distributed, "~> 3.0"},
    # Required for caching decorators (recommended)
    {:decorator, "~> 1.4"},
    # Required for telemetry events (recommended)
    {:telemetry, "~> 1.0"},
    # Required for :shards backend in local adapter
    {:shards, "~> 1.1"}
  ]
end
```

Let's set up the partitioned cache by using the `mix` task
`mix nbx.gen.cache.partitioned`:

```
mix nbx.gen.cache.partitioned -c Blog.PartitionedCache
```

As we saw previously, this command will generate the cache in
`lib/bolg/partitioned_cache.ex` (in this case using the partitioned adapter)
module along with the initial configuration in `config/config.exs`.

The cache:

```elixir
defmodule Blog.PartitionedCache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Partitioned,
    primary_storage_adapter: Nebulex.Adapters.Local
end
```

And the config:

```elixir
config :blog, Blog.PartitionedCache,
  primary: [
    # When using :shards as backend
    backend: :shards,
    # GC interval for pushing new generation: 12 hrs
    gc_interval: :timer.hours(12),
    # Max 1 million entries in cache
    max_size: 1_000_000,
    # Max 2 GB of memory
    allocated_memory: 2_000_000_000,
    # GC memory check interval
    gc_memory_check_interval: :timer.seconds(10)
  ]
```

And remember to add the new cache `Blog.PartitionedCache` to your application's
supervision tree (such as we did it previously):

```elixir
def start(_type, _args) do
  children = [
    Blog.Cache,
    Blog.PartitionedCache
  ]

  ...
```

Now we are ready to start using our partitioned cache!

#### Timeout option

The `Nebulex.Adapters.Partitioned` supports `:timeout` option, it is a value in
milliseconds for the command that will be executed.

```elixir
iex> Blog.PartitionedCache.get("foo", timeout: 10)
#=> {:ok, value}

# when the command's call timed out an error is returned
iex> Blog.PartitionedCache.put("foo", "bar", timeout: 10)
#=> {:error, %Nebulex.Error{reason: :timeout}}
```

To learn more about how partitioned cache works, please check
`Nebulex.Adapters.Partitioned` documentation, and also it is recommended see the
[partitioned cache example](https://github.com/elixir-nebulex/nebulex_examples/tree/main/partitioned_cache).

### Multilevel Cache

Nebulex also provides the adapter `Nebulex.Adapters.Multilevel`, which allows to
setup a multi-level caching hierarchy. The adapter is also included in the
`:nebulex_distributed` dependency.

Let's set up the multilevel cache by using the `mix` task
`mix nbx.gen.cache.multilevel`:

```
mix nbx.gen.cache.multilevel -c Blog.NearCache
```

By default, the command generates a 2-level near-cache topology. The first
level or `L1` using `Nebulex.Adapters.Local` adapter, and the second one or `L2`
using `Nebulex.Adapters.Partitioned` adapter.

The generated cache module `lib/blog/near_cache.ex`:

```elixir
defmodule Blog.NearCache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Multilevel

  ## Cache Levels

  # Default auto-generated L1 cache (local)
  defmodule L1 do
    use Nebulex.Cache,
      otp_app: :blog,
      adapter: Nebulex.Adapters.Local
  end

  # Default auto-generated L2 cache (partitioned cache)
  defmodule L2 do
    use Nebulex.Cache,
      otp_app: :blog,
      adapter: Nebulex.Adapters.Partitioned
  end
end
```

And the configuration (`config/config.exs`):

```elixir
config :blog, Blog.NearCache,
  model: :inclusive,
  levels: [
    # Default auto-generated L1 cache (local)
    {
      Blog.NearCache.L1,
      # GC interval for pushing new generation: 12 hrs
      gc_interval: :timer.hours(12),
      # Max 1 million entries in cache
      max_size: 1_000_000
    },
    # Default auto-generated L2 cache (partitioned cache)
    {
      Blog.NearCache.L2,
      primary: [
        # GC interval for pushing new generation: 12 hrs
        gc_interval: :timer.hours(12),
        # Max 1 million entries in cache
        max_size: 1_000_000
      ]
    }
  ]
```

> Remember you can add `backend: :shards` to use Shards as backend.

Finally, add the new cache `Blog.NearCache` to your application's supervision
tree (such as we did it previously):

```elixir
def start(_type, _args) do
  children = [
    Blog.Cache,
    Blog.PartitionedCache,
    Blog.NearCache
  ]

  ...
```

Let's try it out!

```elixir
iex> Blog.NearCache.put("foo", "bar", ttl: :timer.hours(1))
:ok

iex> Blog.NearCache.get!("foo")
"bar"
```

To learn more about how multilevel-cache works, please check
`Nebulex.Adapters.Multilevel` documentation, and also it is recommended see the
[near cache example](https://github.com/elixir-nebulex/nebulex_examples/tree/main/near_cache).

## Next

* [Decorators-based DSL for cache usage patterns][cache-usage-patterns].

[cache-usage-patterns]: http://hexdocs.pm/nebulex/3.0.0-rc.2/cache-usage-patterns.html
