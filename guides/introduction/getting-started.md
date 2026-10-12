# Getting Started

This guide introduces [Nebulex][nbx_repo], a local and distributed
caching toolkit for Elixir. The API follows the design of
[Ecto](https://github.com/elixir-ecto/ecto): it is simple and adapters are
pluggable, so you can write your own cache (adapter) implementation. In this
guide we cover the basics: how to write, read, and delete cache entries.

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

All dependencies are optional, including the adapters, so you only load what
you need:

  * For [declarative decorator-based caching](`Nebulex.Caching`), add
    `:decorator`.

  * For Telemetry events, add `:telemetry`. See the
    [Info API guide](info-api.md) for cache stats and metrics.

  * For heavy workloads on `Nebulex.Adapters.Local`, you may want `:shards`
    as the backend (partitioned ETS tables). In that case, add `:shards`.

Install these dependencies by running:

```bash
mix deps.get
```

### Step 2: Generate Cache Configuration

Next, define a cache and its configuration so the application code can use
it. Generate both by running:

```bash
mix nbx.gen.cache -c Blog.Cache
```

The command adds this configuration to `config/config.exs`:

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

It also creates the `Blog.Cache` module in `lib/blog/cache.ex`:

```elixir
defmodule Blog.Cache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Local
end
```

This module is what we use to talk to the cache. It calls `use Nebulex.Cache`
and needs the `:otp_app` option, which tells Nebulex which application holds
the cache configuration. Here it is `:blog`, so Nebulex reads the
configuration we just set up in `config/config.exs`.

### Step 3: Add to Supervision Tree

The last step is to add `Blog.Cache` to the application's supervision tree,
in `lib/blog/application.ex`, inside the `start/2` function:

```elixir
def start(_type, _args) do
  children = [
    Blog.Cache
  ]

  # ... rest of your supervision tree
```

This starts the cache process. Without it the cache cannot be used.

> **Important:** Put the cache first in the children list, or at least
> before the processes that use it. Otherwise a process may try to use the
> cache before it has started and raise.

---

## Inserting Entries

We can insert new entries into our blog cache with this code:

```elixir
iex> user = %{id: 1, first_name: "Galileo", last_name: "Galilei"}
iex> Blog.Cache.put(user[:id], user, ttl: :timer.hours(1))
:ok
```

`put` stores a key/value entry in the cache behind `Blog.Cache`.

You can also insert several entries at once:

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

`put` creates the entry if it doesn't exist and overwrites it (including the
`:ttl`) if it does. When you only want to write if the key is absent, or only
if it is present, use `put_new` or `replace` instead.

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

The most common read is fetching an entry by key.

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

There is a function `has_key?` to check if a key exists in the cache:

```elixir
iex> Blog.Cache.has_key?(1)
{:ok, true}

iex> Blog.Cache.has_key?(10)
{:ok, false}
```

## Updating entries

`update` and `get_and_update` change an entry based on its current value:

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
> and `update!`.

## Fetch or Store and Get or Store

`fetch_or_store` and `get_or_store` read a key and, on a miss, run the given
function to compute the value and store it. Use them to load data lazily, to
cache expensive work such as database queries or API calls, and for the
cache-aside pattern (check the cache first, fall back to the source).

The difference between the two is what they do with the function's return
value:

- `fetch_or_store` expects the function to return `{:ok, value}` or
  `{:error, reason}` and only caches successful results.
- `get_or_store` always caches whatever the function returns, including error
  tuples.

### Fetch or Store

Use `fetch_or_store` to cache only successful results and handle errors
yourself:

```elixir
# Cache successful API responses, but don't cache errors
iex> Blog.Cache.fetch_or_store("user:123", fn ->
...>   case fetch_user_from_api(123) do
...>     {:ok, user} -> {:ok, user}
...>     {:error, reason} -> {:error, reason}
...>   end
...> end)
{:ok, %{id: 123, name: "John Doe"}}

# If the function returns an error, it is wrapped in a `Nebulex.Error` and
# nothing is cached
iex> {:error, %Nebulex.Error{reason: reason}} =
...>   Blog.Cache.fetch_or_store("user:999", fn ->
...>     {:error, "User not found"}
...>   end)
iex> reason
"User not found"

# Subsequent calls will still execute the function since errors aren't cached
iex> {:error, %Nebulex.Error{reason: reason}} =
...>   Blog.Cache.fetch_or_store("user:999", fn ->
...>     {:error, "User not found"}
...>   end)
iex> reason
"User not found"
```

### Get or Store

Use `get_or_store` to cache whatever the function returns, including error
responses:

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

Use `fetch_or_store` when only successful results should be cached, for
example when calling an external API whose transient failures you want to
retry rather than remember.

Use `get_or_store` when the result should be cached whatever it is, errors
included, for example to stop retrying a rate-limited API, or when the
function cannot fail and you just want its value cached.

> **Note**: These are composite operations. By default they read with `fetch`,
> run the given function in the calling process, and write with `put`. Those
> steps are not atomic. If the adapter supports transactions, wrap the call in
> `transaction/2` locking the key; the lock coordinates only writers that use
> transactions on the same key. Adapters may override this behavior; see
> `Nebulex.Adapter.CompositeKV`.

## Counters

The function `incr` is provided to increment or decrement a counter; by default,
a counter is initialized to `0`. Let's see how counters work:

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
before deleting it:

```elixir
iex> Blog.Cache.take(2)
{:ok, %{id: 2, first_name: "Charles", last_name: "Darwin"}}

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
iex> Blog.Cache.ttl(3)
{:ok, :infinity}

# If the key doesn't exist an error tuple is returned
iex> {:error, %Nebulex.KeyError{} = e} = Blog.Cache.ttl("nonexistent")
iex> e.key
"nonexistent"

# Same as `ttl` but an exception is raised if an error occurs
iex> Blog.Cache.ttl!(3)
:infinity
```

You could also change or update the expiration time using `expire`, like so:

```elixir
iex> Blog.Cache.expire(3, :timer.hours(1))
{:ok, true}

# When the key doesn't exist false is returned
iex> Blog.Cache.expire("nonexistent", :timer.hours(1))
{:ok, false}

# Same as `expire` but an exception is raised if an error occurs
iex> Blog.Cache.expire!(3, :timer.hours(1))
true
```

## Query and/or Stream entries

Nebulex has functions to fetch, count, delete, or stream all the entries
that match a query.

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
# is a tuple `{:entry, key, value, touched, exp, tag}`, then the match
# spec could be something like:
iex> spec = [{{:entry, :"$1", :"$2", :_, :_, :_}, [{:>, :"$1", 10}], [{{:"$1", :"$2"}}]}]
iex> Blog.Cache.get_all(query: spec)
{:ok, _all_matched}

# using Ex2ms
iex> import Ex2ms
iex> spec =
...>   fun do
...>     {:entry, key, value, _, _, _} when key > 10 -> {key, value}
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

`delete_all/2` removes the matched entries in one call and returns how many
were removed. Without a query it deletes every entry, which is how you flush
the cache:

```elixir
iex> Blog.Cache.delete_all()
{:ok, _num_of_removed_entries}

# raises an exception in case of error
iex> Blog.Cache.delete_all!()
_num_of_removed_entries
```

You can also delete a list of keys at once:

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

# using `Nebulex.Adapters.Local` adapter (entries are
# `{:entry, key, value, touched, exp, tag}` tuples)
iex> spec = [{{:entry, :"$1", :"$2", :_, :_, :_}, [{:<, :"$1", 3}], [{{:"$1", :"$2"}}]}]
iex> {:ok, stream} = Blog.Cache.stream(query: spec)
iex> Enum.to_list(stream)
_all_matched

# using Ex2ms
iex> import Ex2ms
iex> spec =
...>   fun do
...>     {:entry, key, value, _, _, _} when key < 3 -> {key, value}
...>   end
iex> {:ok, stream} = Blog.Cache.stream(query: spec)
iex> Enum.to_list(stream)
_all_matched
```

## Cache Info API

Since v3, Nebulex has an API for getting information about the cache,
including stats.

Nebulex suggests the items `:server`, `:memory`, and `:stats`, but each
adapter decides which items it returns, so check the adapter documentation.
This example uses the official local adapter, which supports the suggested
items.

```elixir
# Returns all information items
iex> {:ok, info} = Blog.Cache.info()
iex> info
%{
  server: %{
    nbx_version: "3.1.0",
    cache_module: Blog.Cache,
    cache_adapter: Nebulex.Adapters.Local,
    cache_name: Blog.Cache,
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
  nbx_version: "3.1.0",
  cache_module: Blog.Cache,
  cache_adapter: Nebulex.Adapters.Local,
  cache_name: Blog.Cache,
  cache_pid: #PID<0.111.0>
}

# Returns the given items
iex> Blog.Cache.info!([:server, :stats])
%{
  server: %{
    nbx_version: "3.1.0",
    cache_module: Blog.Cache,
    cache_adapter: Nebulex.Adapters.Local,
    cache_name: Blog.Cache,
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

Since v3, you can register event listeners that run after a cache entry
changes. Use them for monitoring, logging, or analytics.

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
#=>   pid: #PID<0.111.0>,
#=>   type: :inserted,
#=>   target: {:key, "user:123"},
#=>   command: :put,
#=>   metadata: %{extra_metadata: %{}}
#=> }

iex> Blog.Cache.replace("user:123", %{id: 123, name: "John Doe", email: "john@example.com"})
{:ok, true}

#=> Cache Event: %Nebulex.Event.CacheEntryEvent{
#=>   cache: Blog.Cache,
#=>   name: Blog.Cache,
#=>   pid: #PID<0.111.0>,
#=>   type: :updated,
#=>   target: {:key, "user:123"},
#=>   command: :replace,
#=>   metadata: %{extra_metadata: %{}}
#=> }

iex> Blog.Cache.delete("user:123")
:ok

#=> Cache Event: %Nebulex.Event.CacheEntryEvent{
#=>   cache: Blog.Cache,
#=>   name: Blog.Cache,
#=>   pid: #PID<0.111.0>,
#=>   type: :deleted,
#=>   target: {:key, "user:123"},
#=>   command: :delete,
#=>   metadata: %{extra_metadata: %{}}
#=> }
```

### Event Types and Commands

Each event has a type that depends on the command that caused it:

- `:inserted` - an entry was added by `put`, `put_new`, `put_all`,
  `put_new_all`, or by `incr`/`decr` on a missing counter.
- `:updated` - an existing entry was changed by `replace`, `expire`, `touch`,
  or by `incr`/`decr` on an existing counter.
- `:deleted` - an entry was removed by `delete`, `take`, or `delete_all`.
- `:expired` - a read (`fetch`, `take`, `ttl`, `has_key?`) found the entry
  had expired.

### Advanced Event Handling with Filters

A filter limits which events a listener receives. It is a function that
returns `true` to pass the event to the listener or `false` to drop it.
Filtering this way keeps the listener focused on its own work, and the same
filter function can be reused by several listeners.

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

  def filter_user_keys(%{target: {:key, "user:" <> _}}), do: true
  def filter_user_keys(_other), do: false
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
{:ok, true}
#=> User cache event: updated for user:456
# (no insertion event since replace doesn't trigger :inserted type)
```

### Event Metadata and Context

You can attach metadata to a listener; it comes back in every event:

```elixir
defmodule Blog.Cache.MonitoringHandler do
  # The metadata given on registration comes back as a map, along with the
  # `:extra_metadata` key (the `:telemetry_metadata` option of the command)
  def handle_with_context(%{metadata: metadata} = event) do
    case metadata do
      %{environment: env, service: service} ->
        IO.puts("[#{env}] #{service}: #{event.type} event for #{inspect(event.target)}")

      %{level: level} ->
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

You can register several listeners and remove them one by one:

```elixir
# Register with an explicit id so you can unregister it later
iex> Blog.Cache.register_event_listener(
...>   &Blog.Cache.EventHandler.handle/1,
...>   id: :general_logger
...> )
:ok

iex> Blog.Cache.register_event_listener(
...>   &Blog.Cache.AnalyticsHandler.handle_insertions/1,
...>   id: :analytics
...> )
:ok

# Unregister specific listeners
iex> Blog.Cache.unregister_event_listener(:general_logger)
:ok

iex> Blog.Cache.unregister_event_listener(:analytics)
:ok
```

### Performance Considerations

Listeners run synchronously in the process that called the cache command,
so a slow listener slows down that call. Keep listeners light:

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

> **Note**: Listeners run after the cache command completes, so they don't
> change its result.

## Distributed cache topologies

### Partitioned Cache

`Nebulex.Adapters.Partitioned` gives you a partitioned cache topology. First
add `:nebulex_distributed` to the dependencies in `mix.exs`:

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

Then generate the cache with `mix nbx.gen.cache`:

```
mix nbx.gen.cache -c Blog.PartitionedCache
```

This command generates the cache module in `lib/blog/partitioned_cache.ex`
along with the initial configuration in `config/config.exs`. By default,
the generated cache uses `Nebulex.Adapters.Local`. To use the partitioned
adapter, update the generated cache module as follows:

```elixir
defmodule Blog.PartitionedCache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Partitioned
end
```

The partitioned adapter uses `Nebulex.Adapters.Local` as primary storage
by default. To use a different adapter, provide the
`adapter_opts: [primary_storage_adapter: ...]` option:

```elixir
defmodule Blog.PartitionedCache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Partitioned,
    adapter_opts: [primary_storage_adapter: Nebulex.Adapters.Cachex]
end
```

Then update the generated configuration. The partitioned adapter stores
data in a local cache on each node, so the configuration options must be
wrapped in the `primary: [...]` option:

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
supervision tree (as we did previously):

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

`Nebulex.Adapters.Partitioned` supports a `:timeout` option, in milliseconds,
for each command:

```elixir
iex> Blog.PartitionedCache.get("foo", timeout: 10)
#=> {:ok, value}

# when the command's call times out, an error tuple is returned; the
# `:reason` carries the RPC error, for example
# `{:rpc, {:error, :timeout}}`
iex> Blog.PartitionedCache.put("foo", "bar", timeout: 10)
#=> {:error, %Nebulex.Error{reason: {:rpc, {:error, :timeout}}}}
```

For more on how the partitioned cache works, see the
`Nebulex.Adapters.Partitioned` docs and the
[partitioned cache example](https://github.com/elixir-nebulex/nebulex_examples/tree/main/partitioned_cache).

### Multilevel Cache

`Nebulex.Adapters.Multilevel`, also in `:nebulex_distributed`, gives you a
multi-level cache hierarchy.

Unlike the local adapter, the multilevel adapter needs the cache levels
defined by hand. Create `lib/blog/near_cache.ex` like this:

```elixir
defmodule Blog.NearCache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Multilevel

  ## Cache Levels

  # L1 cache (local)
  defmodule L1 do
    use Nebulex.Cache,
      otp_app: :blog,
      adapter: Nebulex.Adapters.Local
  end

  # L2 cache (partitioned cache)
  defmodule L2 do
    use Nebulex.Cache,
      otp_app: :blog,
      adapter: Nebulex.Adapters.Partitioned
  end
end
```

This defines a 2-level near-cache topology with `L1` using the local adapter
and `L2` using the partitioned adapter.

Then add the configuration to `config/config.exs`:

```elixir
config :blog, Blog.NearCache,
  inclusion_policy: :inclusive,
  levels: [
    # L1 cache (local)
    {
      Blog.NearCache.L1,
      # GC interval for pushing new generation: 12 hrs
      gc_interval: :timer.hours(12),
      # Max 1 million entries in cache
      max_size: 1_000_000
    },
    # L2 cache (partitioned cache)
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
tree (as we did previously):

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

For more on how the multilevel cache works, see the
`Nebulex.Adapters.Multilevel` docs and the
[near cache example](https://github.com/elixir-nebulex/nebulex_examples/tree/main/near_cache).

## Next

* [Decorators-based DSL for cache usage patterns](cache-usage-patterns.md).
