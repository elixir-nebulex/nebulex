# Cache Usage Patterns with Caching Decorators

Nebulex supports several common cache access patterns via
[caching decorators][nbx_caching].

[nbx_caching]: http://hexdocs.pm/nebulex/3.0.0-rc.2/Nebulex.Caching.Decorators.html

> The following documentation about caching patterns is based on
> [EHCache Docs][EHCache]

[EHCache]: https://www.ehcache.org/documentation/3.10/caching-patterns.html

---

## Choosing a Caching Pattern

| Pattern | Best For | Pros | Cons |
|---------|----------|------|------|
| **Cache-Aside** | Simple apps, manual control | Direct code paths, flexibility | App complexity, cache inconsistency risk |
| **Read-Through** | Frequent reads, consistent loading | Simpler app code, automatic loading | Cache hide performance issues |
| **Write-Through** | Critical data, consistency | Cache/SoR in sync, safe | Performance overhead, blocking |
| **Cache-as-SoR** | High-throughput, abstraction preferred | Cleanest code, abstracted SoR | Black box behavior, harder debugging |

---

## Cache-Aside

The **cache-aside** pattern involves direct cache usage in application code.

When accessing the system-of-record (SoR), the application first checks the
cache. If the data exists in the cache, it's returned directly, bypassing the
SoR. Otherwise, the application fetches the data from the SoR, stores it in the
cache, and then returns it. When writing data, both the cache and SoR must be
updated.

### Reading Values

**Imperative approach:**

```elixir
# Check cache first, then fall back to SoR
with {:error, _reason} <- MyCache.fetch(key) do
  value = SoR.get(key)  # e.g., Ecto.Repo
  MyCache.put(key, value)
  value
end
```

**Declarative approach (with `cacheable` decorator):**

```elixir
defmodule MyApp.Users do
  use Nebulex.Caching, cache: MyApp.Cache

  # Cache-aside: automatically check cache, load from SoR if miss
  @decorate cacheable(key: user_id)
  def get_user(user_id) do
    MyApp.Repo.get(User, user_id)
  end
end
```

### Writing Values

**Imperative approach:**

```elixir
# Update both cache and SoR
MyCache.put(key, value)
SoR.insert(key, value)  # e.g., Ecto.Repo
```

**Declarative approach (with `cache_put` or `cache_evict` decorators):**

```elixir
# Option 1: Update cache when SoR is updated
@decorate cache_put(key: user_id)
def update_user(user_id, attrs) do
  MyApp.Repo.update!(User, attrs)
end

# Option 2: Evict cache when SoR is updated (let next read reload)
@decorate cache_evict(key: user_id)
def delete_user(user_id) do
  MyApp.Repo.delete!(User, user_id)
end
```

This is the default behavior for most caches, requiring direct interaction with
both the cache and the SoR (typically a database). The decorator-based approach
automates cache management while keeping the pattern explicit in the code.

---

## Cache-as-SoR

The **cache-as-SoR** pattern uses the cache as the primary system-of-record
(SoR). The pattern delegates SoR reading and writing activities to the cache,
so that application code is (at least directly) absolved of this responsibility.
To implement the cache-as-SoR pattern, use a combination of the following
read and write patterns:

 * **Read-through**
 * **Write-through**

### Advantages

* **Less cluttered application code** (improved maintainability through
  centralized SoR read/write operations).
* **Choice of write-through or write-behind strategies** on a per-cache basis.
* **Allows the cache to solve the thundering-herd problem**.

### Disadvantages

* **Less directly visible code-path** – Behavior is abstracted and less obvious
  when reading the code. However, this is where declarative decorator-based
  caching comes in. Nebulex provides decorators to abstract most of the logic
  behind **Read-through** and **Write-through** patterns and make the
  implementation extremely easy.

---

## Read-Through

Under the **read-through** pattern, the cache is configured with a loader
component that knows how to load data from the system-of-record (SoR).

When the cache is asked for the value associated with a given key and such an
entry does not exist within the cache, the cache invokes the loader to retrieve
the value from the SoR, then caches the value, and finally returns it to the
caller.

The next time the cache is asked for the value for the same key, it can be
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

---

## Implementing Patterns with Decorators

The following table summarizes which decorators support which caching patterns:

| Pattern | Decorator | Use Case |
|---------|-----------|----------|
| **Cache-Aside** | `@cacheable` | Reads: Check cache, load from SoR if miss |
| **Read-Through** | `@cacheable` | Same as cache-aside but emphasizes automatic loading |
| **Write-Through (Update)** | `@cache_put` | Writes: Update cache AND SoR together |
| **Write-Through (Invalidate)** | `@cache_evict` | Writes: Invalidate cache, next read reloads from SoR |

Each decorator handles cache management automatically:

- **`@cacheable`** - Implements the read-through pattern by checking the cache
  first and invoking the function body to load from SoR on miss
- **`@cache_put`** - Implements write-through with cache update by invoking the
  function (writing to SoR) and then storing the result in cache
- **`@cache_evict`** - Implements write-through with cache invalidation by
  invoking the function (writing to SoR) and then removing the cache entry

For more details and advanced usage, see the Declarative Caching guide.

---

## Next Read

Now that you understand the common caching patterns, learn how to implement them
in your Nebulex applications:

- **[Declarative Caching with Decorators](http://hexdocs.pm/nebulex/3.0.0-rc.2/declarative-caching.html)**
  - Comprehensive guide to using `@cacheable`, `@cache_put`, and `@cache_evict`
    decorators with real-world examples and advanced patterns
  - Reference documentation for all decorator options and behaviors
