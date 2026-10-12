# Cache Usage Patterns with Caching Decorators

Nebulex supports the common cache access patterns through
[caching decorators](`Nebulex.Caching.Decorators`).

> The description of the patterns below is based on the
> [EHCache docs][EHCache].

[EHCache]: https://www.ehcache.org/documentation/3.10/caching-patterns.html

> **Note**: Caching decorators require the `:decorator` dependency. Add
> `{:decorator, "~> 1.4"}` to your `mix.exs`.

## Choosing a Caching Pattern

| Pattern | Best For | Pros | Cons |
|---------|----------|------|------|
| Cache-Aside | Simple apps, manual control | Direct code paths, flexibility | More application code, risk of cache inconsistency |
| Read-Through | Frequent reads, consistent loading | Simpler application code, automatic loading | The cache can hide performance problems |
| Write-Through | Critical data, consistency | Cache and SoR stay in sync | Performance overhead, blocking writes |
| Cache-as-SoR | High throughput, abstraction preferred | Cleanest code, SoR hidden behind the cache | Less visible behavior, harder debugging |

## Cache-Aside

In the cache-aside pattern the application code uses the cache directly.

When accessing the system-of-record (SoR), the application first checks the
cache. If the data exists in the cache, it's returned directly, bypassing the
SoR. Otherwise, the application fetches the data from the SoR, stores it in the
cache, and then returns it. When writing data, both the cache and SoR must be
updated.

### Reading Values

Imperative approach:

```elixir
# Check cache first, then fall back to SoR
with {:error, _reason} <- MyCache.fetch(key) do
  value = SoR.get(key)  # e.g., Ecto.Repo
  MyCache.put(key, value)
  value
end
```

Declarative approach, with the `cacheable` decorator:

```elixir
defmodule MyApp.Users do
  use Nebulex.Caching, cache: MyApp.Cache

  # Cache-aside: check the cache, load from the SoR on a miss
  @decorate cacheable(key: user_id)
  def get_user(user_id) do
    MyApp.Repo.get(User, user_id)
  end
end
```

### Writing Values

Imperative approach:

```elixir
# Update both cache and SoR
MyCache.put(key, value)
SoR.insert(key, value)  # e.g., Ecto.Repo
```

Declarative approach, with the `cache_put` or `cache_evict` decorators:

```elixir
# Option 1: Update cache when SoR is updated
@decorate cache_put(key: user.id)
def update_user(user, attrs) do
  user
  |> User.changeset(attrs)
  |> MyApp.Repo.update!()
end

# Option 2: Evict cache when SoR is updated (let next read reload)
@decorate cache_evict(key: user.id)
def delete_user(user) do
  MyApp.Repo.delete!(user)
end
```

This is the default behavior for most caches: the application talks to both
the cache and the SoR (typically a database). The decorators take care of the
cache calls while keeping the pattern visible in the code.

## Cache-as-SoR

The cache-as-SoR pattern uses the cache as the primary system-of-record
(SoR). Reading from and writing to the SoR is delegated to the cache, so the
application code does not do it directly. To implement the cache-as-SoR
pattern, combine the following read and write patterns:

 * Read-through
 * Write-through

### Advantages

* Less cluttered application code, since the SoR reads and writes live in one
  place.
* Choice of write-through or write-behind strategies on a per-cache basis.
* The cache can solve the thundering-herd problem.

### Disadvantages

* The code path is less visible, since the behavior is hidden behind the
  cache. This is where the decorators help: they cover most of the logic
  behind the read-through and write-through patterns, so the implementation
  is short.

## Read-Through

In the read-through pattern, the cache is configured with a loader that knows
how to load data from the system-of-record (SoR).

When the cache is asked for the value associated with a given key and such an
entry does not exist within the cache, the cache invokes the loader to retrieve
the value from the SoR, then caches the value, and finally returns it to the
caller.

The next time the cache is asked for the value for the same key, it can be
returned from the cache without using the loader (unless the entry has been
evicted or expired).

This pattern can be implemented with the `cacheable` decorator as follows:

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

The loader that retrieves the value from the system-of-record (SoR) is the
function body itself.

## Write-through

In the write-through pattern, the cache is configured with a writer that knows
how to write data to the system-of-record (SoR).

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

The logic that writes data to the system-of-record (SoR) is the function
body itself.

## Implementing Patterns with Decorators

The following table summarizes which decorator implements which pattern:

| Pattern | Decorator | Use Case |
|---------|-----------|----------|
| Cache-Aside | `@cacheable` | Reads: check the cache, load from the SoR on a miss |
| Read-Through | `@cacheable` | Same as cache-aside, with the loading done for you |
| Write-Through (Update) | `@cache_put` | Writes: update the cache and the SoR together |
| Write-Through (Invalidate) | `@cache_evict` | Writes: invalidate the cache; the next read reloads from the SoR |

What each decorator does:

- `@cacheable` checks the cache first and runs the function body to load
  from the SoR on a miss (read-through).
- `@cache_put` runs the function (writing to the SoR) and then stores the
  result in the cache (write-through with update).
- `@cache_evict` runs the function (writing to the SoR) and then removes the
  cache entry (write-through with invalidation).

For more details, see the Declarative Caching guide.

## Next Read

Now that you know the common caching patterns, see how to use them in your
application:

- [Declarative Caching with Decorators](declarative-caching.md): a guide to
  the `@cacheable`, `@cache_put`, and `@cache_evict` decorators, with
  examples, plus the reference for all decorator options.
