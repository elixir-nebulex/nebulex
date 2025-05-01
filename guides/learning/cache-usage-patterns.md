# Cache usage patterns with caching decorators

Nebulex supports several common cache access patterns via
[caching decorators][nbx_caching].

[nbx_caching]: http://hexdocs.pm/nebulex/3.0.0-rc.1/Nebulex.Caching.Decorators.html

> The following documentation about caching patterns is based on
> [EHCache Docs][EHCache]

[EHCache]: https://www.ehcache.org/documentation/3.10/caching-patterns.html

## Cache-aside

The cache-aside pattern involves direct cache usage in application code.

When accessing the system-of-record (SoR), the application first checks the
cache. If the data exists in the cache, it's returned directly, bypassing the
SoR. Otherwise, the application fetches the data from the SoR, stores it in the
cache, and then returns it. When writing data, both the cache and SoR must be
updated.

### Reading values

```elixir
# Check cache first, then fall back to SoR
with {:error, _reason} <- MyCache.fetch(key) do
  value = SoR.get(key)  # e.g., Ecto.Repo
  MyCache.put(key, value)
  value
end
```

### Writing values

```elixir
# Update both cache and SoR
MyCache.put(key, value)
SoR.insert(key, value)  # e.g., Ecto.Repo
```

This is the default behavior for most caches, requiring direct interaction with
both the cache and the SoR (typically a database).

## Cache-as-SoR

The cache-as-SoR pattern uses the cache as the primary system-of-record (SoR).

The pattern delegates SoR reading and writing activities to the cache, so that
application code is (at least directly) absolved of this responsibility.
To implement the cache-as-SoR pattern, use a combination of the following
read and write patterns:

 * **Read-through**

 * **Write-through**

Advantages of using the cache-as-SoR pattern are:

 * Less cluttered application code (improved maintainability through centralized
   SoR read/write operations)

 * Choice of write-through or write-behind strategies on a per-cache basis

 * Allows the cache to solve the thundering-herd problem

A disadvantage of using the cache-as-SoR pattern is:

 * Less directly visible code-path

But how to get all this out-of-box? This is where declarative decorator-based
caching comes in. Nebulex provides a set of annotation to abstract most of the
logic behind **Read-through** and **Write-through** patterns and make the
implementation extremely easy. But let's go over these patterns more in detail
and how to implement them by using [Nebulex decorators][nbx_caching].

## Read-through

Under the read-through pattern, the cache is configured with a loader component
that knows how to load data from the system-of-record (SoR).

When the cache is asked for the value associated with a given key and such an
entry does not exist within the cache, the cache invokes the loader to retrieve
the value from the SoR, then caches the value, then returns it to the caller.

The next time the cache is asked for the value for the same key it can be
returned from the cache without using the loader (unless the entry has been
evicted or expired).

This pattern can be easily implemented using the `cacheable` decorator
as follows:

```elixir
defmodule MyApp.Example do
  use Nebulex.Caching, cache: MyApp.Cache

  @ttl :timer.hours(1)

  @decorate cacheable(key: name)
  def get_by_name(name) do
    # your logic (the loader to retrieve the value from the SoR)
  end

  @decorate cacheable(key: age, opts: [ttl: @ttl])
  def get_by_age(age) do
    # your logic (the loader to retrieve the value from the SoR)
  end

  @decorate cacheable()
  def all(query) do
    # your logic (the loader to retrieve the value from the SoR)
  end
end
```

As you can see, the loader to retrieve the value from the system-of-record (SoR)
is the function logic itself.

## Write-through

Under the write-through pattern, the cache is configured with a writer component
that knows how to write data to the system-of-record (SoR).

When the cache is asked to store a value for a key, the cache invokes the writer
to store the value in the SoR, as well as updating (or deleting) the cache.

This pattern can be implemented using `cache_evict` or `cache_put` decorators.
When the data is written to the system-of-record (SoR), you can update the
cached value associated with the given key using `cache_put`, or just delete
it using `cache_evict`.

```elixir
defmodule MyApp.Example do
  use Nebulex.Caching, cache: MyApp.Cache

  # When the data is written to the SoR, it is updated in the cache
  @decorate cache_put(key: something)
  def update(something) do
    # Write data to the SoR (most likely the Database)
  end

  # When the data is written to the SoR, it is deleted (evicted) from the cache
  @decorate cache_evict(key: something)
  def update_something(something) do
    # Write data to the SoR (most likely the Database)
  end
end
```

As you can see, the logic to write data to the system-of-record (SoR) is the
function logic itself.
