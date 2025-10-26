# Declarative Caching: Patterns and Best Practices

This guide provides comprehensive examples and best practices for using
Nebulex's caching decorators. While the [Decorators API documentation][decorators_api]
covers all options and basic usage, this guide focuses on real-world
scenarios, adapter-specific optimizations, and advanced patterns.

[decorators_api]: http://hexdocs.pm/nebulex/3.0.0-rc.2/Nebulex.Caching.Decorators.html

---

## Introduction

Nebulex provides three main decorators for implementing declarative caching:

- **`@decorate cacheable`** - Read-through caching (cache-aside pattern)
- **`@decorate cache_put`** - Write-through caching (always execute
  and cache result)
- **`@decorate cache_evict`** - Cache invalidation (remove entries)

These decorators abstract away the complexity of cache management,
allowing you to focus on your business logic while maintaining clean,
maintainable code.

### Setup

First, enable caching decorators in your module:

```elixir
defmodule MyApp.Products do
  use Nebulex.Caching,
    cache: MyApp.Cache,
    on_error: :nothing

  # Your decorated functions here...
end
```

The `use` macro accepts several options that become defaults for all decorated
functions in the module:

- `:cache` - The default cache to use
- `:on_error` - How to handle cache errors (`:nothing` or `:raise`)
- `:match` - Default match function for conditional caching
- `:opts` - Default options passed to cache operations (e.g., TTL)

---

## Quick Start: Basic Usage

Let's start with a simple product catalog to illustrate the basics. For complete
API documentation on all three decorators, see [Nebulex.Caching.Decorators API][decorators_api].

### Reading with `@cacheable`

```elixir
@decorate cacheable(key: id, opts: [ttl: :timer.hours(1)])
def get_product(id) do
  # This only runs if the value is not in cache
  Repo.get(Product, id)
end
```

**How it works:**
1. First call: Cache miss → executes function → stores result
   → returns value
2. Subsequent calls: Cache hit → returns cached value directly
3. After 1 hour: TTL expires → cache miss on next call

### Writing with `@cache_put`

```elixir
@decorate cache_put(
            key: product.id,
            match: &match_ok/1,
            opts: [ttl: :timer.hours(1)]
          )
def update_product(product, attrs) do
  product
  |> Product.changeset(attrs)
  |> Repo.update()
end

defp match_ok({:ok, product}), do: {true, product}
defp match_ok({:error, _}), do: false
```

**How it works:**
1. Function always executes (no cache check)
2. Match function decides whether to cache the result
3. On success (`{:ok, product}`), the product is cached
4. On error, nothing is cached

### Evicting with `@cache_evict`

```elixir
@decorate cache_evict(key: id)
def delete_product(id) do
  Repo.delete(Product, id)
end
```

**How it works:**
1. Function executes
2. After successful execution, the cache entry is removed

---

## Advanced Eviction Patterns

The `cache_evict` decorator supports several powerful patterns for
cache invalidation. For detailed API documentation and option reference, see
[`cache_evict/3`](http://hexdocs.pm/nebulex/3.0.0-rc.2/Nebulex.Caching.Decorators.html#cache_evict/3).

### Evicting Multiple Keys

Use `{:in, keys}` to evict multiple entries at once:

```elixir
@decorate cache_evict(key: {:in, [product.id, product.slug]})
def delete_product(product) do
  # Evicts both product.id and product.slug keys
  Repo.delete(product)
end
```

### Query-Based Eviction

For bulk eviction based on criteria, use the `:query` option. The query format
depends on your cache adapter.

> #### Adapter-specific queries {: .warning}
>
> Query syntax varies by adapter. The examples in this guide use
> `Nebulex.Adapters.Local`, which supports ETS match specifications.
> For other adapters, consult their documentation.

```elixir
use Nebulex.Adapters.Local.QueryHelper

@decorate cache_evict(query: &query_for_category/1)
def delete_category_products(category_id) do
  # Evicts all products in this category
  Repo.delete_all(from p in Product, where: p.category_id == ^category_id)
end

defp query_for_category(%{args: [category_id]}) do
  # QueryHelper provides a clean DSL for building match specs
  match_spec value: %{category_id: cat_id},
             where: cat_id == ^category_id,
             select: true
end
```

### Combining `:key` and `:query`

You can now use both `:key` and `:query` together for hierarchical eviction:

```elixir
# Using QueryHelper for cleaner syntax
use Nebulex.Adapters.Local.QueryHelper

@decorate cache_evict(
            key: category_id,
            query: &query_for_category_products/1
          )
def delete_category(category_id) do
  # Evicts the category AND all products in that category
  Products.delete_all_for_category(category_id)
  Categories.delete(category_id)
end

defp query_for_category_products(%{args: [category_id]}) do
  match_spec value: %{category_id: cat_id, type: type},
             where: cat_id == ^category_id and type == "product",
             select: true
end
```

**Execution order:**
1. Query-based eviction executes first (removes all products)
2. Key-based eviction executes second (removes the category)

### Eviction Timing

By default, eviction happens **after** the function completes. Use
`:before_invocation` to evict before execution:

```elixir
@decorate cache_evict(key: id, before_invocation: true)
def refresh_product(id) do
  # Cache is cleared before this runs
  fetch_product_from_external_api(id)
end
```

---

## Working with Nebulex.Adapters.Local

The `Nebulex.Adapters.Local` adapter provides several powerful features for
working with cached data. This section covers features introduced in recent
versions that make cache management more intuitive and maintainable.

For complete API documentation, see the
["Local Adapter: Advanced Reference Eviction"](http://hexdocs.pm/nebulex/3.0.0-rc.2/Nebulex.Caching.Decorators.html#cache_evict/3-local-adapter-advanced-reference-eviction)
section in `cache_evict/3`.

### Building Queries with QueryHelper

The `Nebulex.Adapters.Local.QueryHelper` module provides a user-friendly DSL
for building ETS match specifications without writing verbose tuples.

> #### New in `Nebulex.Adapters.Local` v3.0.0 {: .tip}
>
> The QueryHelper makes writing queries much more readable and
> maintainable. See the [QueryHelper documentation][query_helper_docs]
> for more details.

[query_helper_docs]: https://hexdocs.pm/nebulex_local/Nebulex.Adapters.Local.QueryHelper.html

**Without QueryHelper (raw match spec):**

```elixir
defp query_for_category(%{args: [category_id]}) do
  [
    {
      {:entry, :"$1", %{category_id: :"$2"}, :_, :_, :_},
      [{:"=:=", :"$2", category_id}],
      [true]
    }
  ]
end
```

**With QueryHelper (user-friendly DSL):**

```elixir
use Nebulex.Adapters.Local.QueryHelper

defp query_for_category(%{args: [category_id]}) do
  match_spec value: %{category_id: cat_id},
             where: cat_id == ^category_id,
             select: true

end
```

**More complex examples:**

```elixir
use Nebulex.Adapters.Local.QueryHelper

# Match products in a category with price > 100
defp query_expensive_products(%{args: [category_id]}) do
  match_spec value: %{category_id: cat_id, price: price},
             where: cat_id == ^category_id and price > 100,
             select: true
end

# Match products by multiple criteria
defp query_products(%{args: [category_id, status]}) do
  match_spec(
    value: %{
      category_id: cat_id,
      status: st,
      stock: stock
    },
    where: cat_id == ^category_id and st == ^status and stock > 0,
    select: true
  )
end
```

### Entry Tagging for Organization

Entry tagging allows you to logically group cache entries for easier
management and bulk operations.

> #### New in `Nebulex.Adapters.Local` v3.0.0 {: .tip}
>
> Tags provide a way to organize and invalidate groups of related
> entries. See the [Local adapter documentation][local_adapter_docs]
> for more details.

[local_adapter_docs]: https://hexdocs.pm/nebulex_local

**Storing entries with tags:**

```elixir
# Store a product with a category tag
MyCache.put(
  product.id,
  product,
  tag: "category:#{product.category_id}"
)

# Store a user session with a user tag
MyCache.put(
  session_id,
  session_data,
  tag: "user:#{user_id}"
)
```

**Querying by tags:**

```elixir
use Nebulex.Adapters.Local.QueryHelper

# Evict all entries with the :featured tag
@decorate cache_evict(query: &query_by_tag/1)
def refresh_featured_products(tag \\ :featured) do
  FeaturedProducts.refresh()
end

defp query_by_tag(%{args: [tag]}) do
  match_spec tag: t, where: t == ^tag, select: true
end

# Evict all sessions for a specific user
@decorate cache_evict(query: &query_user_sessions/1)
def logout_user(user_id) do
  Sessions.delete_all_for_user(user_id)
end

defp query_user_sessions(%{args: [user_id]}) do
  user_tag = "user:#{user_id}"
  match_spec tag: t, where: t == ^user_tag, select: true
end
```

**Using tags with decorators:**

```elixir
@decorate cacheable(
            key: id,
            opts: [ttl: :timer.hours(1), tag: :catalog]
          )
def get_product(id) do
  Repo.get(Product, id)
end

# Later, evict all catalog entries
@decorate cache_evict(
            query: fn _ ->
              match_spec(tag: t, where: t == :catalog)
            end
          )
def refresh_catalog do
  # Evicts all entries tagged with :catalog
  CatalogCache.refresh()
end
```

### Managing Cache References

Cache references allow you to store a value once and reference it from
multiple keys, avoiding data duplication and ensuring consistency.

> #### New in `Nebulex.Adapters.Local` v3.0.0 {: .tip}
>
> Reference management is integrated with the Local adapter.
> See ["Building Match Specs with QueryHelper"][query_helper_section]
> for more details.

[query_helper_section]: https://hexdocs.pm/nebulex_local/Nebulex.Adapters.Local.html#module-building-match-specs-with-queryhelper

For complete API documentation on the `:references` option, see
[`cacheable/3` - Referenced keys][cacheable_refs_api].

[cacheable_refs_api]: http://hexdocs.pm/nebulex/3.0.0-rc.2/Nebulex.Caching.Decorators.html#cacheable/3-referenced-keys

**Basic reference usage:**

```elixir
@decorate cacheable(
            key: email,
            references: &(&1 && &1.id)
          )
def get_user_by_email(email) do
  Repo.get_by(User, email: email)
end
```

**How it works:**
1. User is fetched and stored under the referenced key (`user.id`)
2. A reference is stored under the primary key (`email`) pointing to `user.id`
3. Subsequent calls with the same `email` follow the reference to get the user

**Cleaning up references:**

When evicting entries with references, you need to handle both the value and
its references. For simple cases, you can manually specify all keys:

```elixir
# Evict both the primary key and the reference
@decorate cache_evict(key: {:in, [user.id, user.email]})
def delete_user(user) do
  # This evicts both the user.id key and the user.email reference
  Repo.delete(user)
end
```

**Using `keyref_match_spec` for automatic reference cleanup:**

When you have multiple references pointing to the same key, use
`keyref_match_spec/2` to automatically find and evict all of them:

```elixir
use Nebulex.Adapters.Local.QueryHelper

@decorate cacheable(key: id)
def get_user(id) do
  Repo.get(User, id)
end

@decorate cacheable(key: email, references: &(&1 && &1.id))
def get_user_by_email(email) do
  Repo.get_by(User, email: email)
end

@decorate cacheable(key: username, references: &(&1 && &1.id))
def get_user_by_username(username) do
  Repo.get_by(User, username: username)
end

# Evict user and ALL references pointing to it
@decorate cache_evict(
            key: user.id,
            query: &user_references_query/1
          )
def delete_user(user) do
  Repo.delete(user)
end

defp user_references_query(%{args: [user]}) do
  # Finds all cache keys that reference this user.id
  keyref_match_spec(user.id)
end
```

**How `keyref_match_spec` works:**
- Finds all reference entries that point to a specific key
- Works across the entire cache (or specific cache if provided)
- Automatically handles the internal reference structure
- Returns a match spec you can use with `cache_evict`

For advanced reference management, see
["Building Match Specs with QueryHelper"][query_helper_section].

**Using TTL to automatically expire references:**

```elixir
@decorate cacheable(
            key: email,
            references: &keyref(&1.id, ttl: :timer.hours(24))
          )
def get_user_by_email(email) do
  Repo.get_by(User, email: email)
end
```

The reference entry expires after 24 hours, preventing stale references even
if the referenced value is updated separately.

**External references across caches:**

When references point to data in a different cache, use `cache:` option in
the references function and specify both caches during eviction:

```elixir
# Store user data in UserCache
@decorate cacheable(cache: UserCache, key: id)
def get_user(id) do
  Repo.get(User, id)
end

# Store reference in EmailLookupCache pointing to user in UserCache
@decorate cacheable(
            cache: EmailLookupCache,
            key: email,
            references: &keyref(&1.id, cache: UserCache)
          )
def get_user_by_email(email) do
  Repo.get_by(User, email: email)
end

# Evict from both caches using keyref() for external cache reference
@decorate cache_evict(
            cache: UserCache,
            key: {:in, [user.id, keyref(user.email, cache: EmailLookupCache)]}
          )
def delete_user(user) do
  Repo.delete(user)
end
```

**How it works:**
- The decorator operates on `UserCache` (where the data is stored)
- `user.id` evicts the data from `UserCache`
- `keyref(user.email, cache: EmailLookupCache)` evicts the reference from
  `EmailLookupCache`
- This is when you actually need `keyref()` - for cross-cache eviction!

### Advanced Reference Cleanup with Tags and Queries

Managing references can be challenging when you have multiple access patterns
pointing to the same value. The `Nebulex.Adapters.Local` adapter provides two
powerful strategies to automatically clean up all references without manually
specifying each one.

#### Strategy 1: Tag-based reference grouping

Tag both the main key and its references with the same tag, then evict all
entries with that tag in a single operation.

**Setup:**

```elixir
use Nebulex.Adapters.Local.QueryHelper

@decorate cacheable(key: id, opts: [tag: "user"])
def get_user(id) do
  Repo.get(User, id)
end

@decorate cacheable(
            key: email,
            references: &(&1 && &1.id),
            opts: [tag: "user"]
          )
def get_user_by_email(email) do
  Repo.get_by(User, email: email)
end

@decorate cacheable(
            key: username,
            references: &(&1 && &1.id),
            opts: [tag: "user"]
          )
def get_user_by_username(username) do
  Repo.get_by(User, username: username)
end

# Evict the user and ALL references by tag
@decorate cache_evict(query: &evict_user_by_tag/1)
def delete_user(user) do
  Repo.delete(user)
end

defp evict_user_by_tag(%{args: [_user]}) do
  match_spec tag: t, where: t == "user", select: true
end
```

**Why this works:**
- All entries (main key and references) share the same tag
- Single query evicts everything in one operation
- Clean and declarative
- Perfect when you control reference creation upfront

**Trade-offs:**
- Requires planning tags during caching setup
- Less granular - evicts all tagged entries, not just one user's

#### Strategy 2: Direct reference queries with keyref_match_spec

Use `keyref_match_spec/2` to automatically discover and evict all references
pointing to a specific key, combined with explicit key eviction.

**Setup:**

```elixir
use Nebulex.Adapters.Local.QueryHelper

@decorate cacheable(key: id)
def get_user(id) do
  Repo.get(User, id)
end

@decorate cacheable(key: email, references: &(&1 && &1.id))
def get_user_by_email(email) do
  Repo.get_by(User, email: email)
end

@decorate cacheable(key: username, references: &(&1 && &1.id))
def get_user_by_username(username) do
  Repo.get_by(User, username: username)
end

# Evict the user AND all references pointing to it
@decorate cache_evict(key: user.id, query: &evict_user_references/1)
def delete_user(user) do
  Repo.delete(user)
end

defp evict_user_references(%{args: [user]}) do
  # Finds all cache keys (reference keys) that point to user.id
  keyref_match_spec(user.id)
end
```

**How it works:**
1. `:key` evicts the main entry (`user.id`)
2. `:query` finds all references pointing to `user.id`
3. Both are evicted in a single operation

**Why this approach:**
- More flexible - discovers references automatically
- Works even if references are created conditionally
- Handles multiple references across different decorators
- Doesn't require upfront tag coordination

**Trade-offs:**
- Slightly more complex than tag-based approach
- Query performs a scan to find references

#### Choosing Between Strategies

| Strategy | Best For | Tradeoff |
|----------|----------|----------|
| **Tags** | Coordinated cleanup, related entries | Requires upfront planning |
| **keyref_match_spec** | Multiple access patterns, flexibility | Slight performance cost for query |
| **Combined** | Maximum robustness | Most complex, but most flexible |

**Recommended approach for production:**

Combine both strategies for the best of both worlds:

```elixir
use Nebulex.Adapters.Local.QueryHelper

@decorate cacheable(key: id, opts: [tag: "user"])
def get_user(id) do
  Repo.get(User, id)
end

@decorate cacheable(key: email, references: &(&1 && &1.id), opts: [tag: "user"])
def get_user_by_email(email) do
  Repo.get_by(User, email: email)
end

@decorate cacheable(key: username, references: &(&1 && &1.id), opts: [tag: "user"])
def get_user_by_username(username) do
  Repo.get_by(User, username: username)
end

# Use both tag and query for maximum robustness:
# - Tag evicts everything if references are properly tagged
# - Query catches any orphaned references as a fallback
@decorate cache_evict(query: &evict_users_by_tag/0)
def delete_all_user_data(user) do
  Repo.delete(user)
end

defp evict_users_by_tag do
  match_spec tag: t, where: t == "user", select: true
end

# For individual user deletion, use keyref_match_spec for flexibility
@decorate cache_evict(key: user.id, query: &evict_user_refs/1)
def delete_user(user) do
  Repo.delete(user)
end

defp evict_user_refs(%{args: [user]}) do
  keyref_match_spec(user.id)
end
```

This layered approach provides:
- ✅ Automatic cleanup through tags (primary method)
- ✅ Fallback cleanup through queries (safety net)
- ✅ No dangling references
- ✅ Clear intent in your code

---

## Real-World Scenario: E-commerce Product Catalog

Let's build a comprehensive example that evolves from simple caching to advanced
patterns, showcasing how different features work together in a real application.

### The Scenario

We're building an e-commerce platform with:
- Products organized in categories
- User sessions and authentication
- Product search and filtering
- Shopping carts
- Administrative operations

We'll progressively add caching patterns to optimize performance.

### Step 1: Basic Product Caching

Start with simple read-through caching for products:

```elixir
defmodule MyApp.Catalog do
  use Nebulex.Caching,
    cache: MyApp.Cache,
    on_error: :nothing

  alias MyApp.Repo
  alias MyApp.Catalog.Product

  @ttl :timer.hours(2)

  @decorate cacheable(key: id, opts: [ttl: @ttl])
  def get_product(id) do
    Repo.get(Product, id)
  end

  @decorate cache_put(key: product.id, match: &match_ok/1, opts: [ttl: @ttl])
  def update_product(product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  @decorate cache_evict(key: id)
  def delete_product(id) do
    Repo.delete(Product, id)
  end

  defp match_ok({:ok, product}), do: {true, product}
  defp match_ok(_), do: false
end
```

### Step 2: Multiple Access Patterns with References

Products can be accessed by ID or slug. Use references to avoid duplication:

```elixir
@decorate cacheable(key: id, opts: [ttl: @ttl])
def get_product(id) do
  Repo.get(Product, id)
end

@decorate cacheable(key: slug, references: &(&1 && &1.id), opts: [ttl: @ttl])
def get_product_by_slug(slug) do
  Repo.get_by(Product, slug: slug)
end

# When evicting, remove both keys
@decorate cache_evict(key: {:in, [product.id, product.slug]})
def delete_product(product) do
  Repo.delete(product)
end
```

**What happens:**
- `get_product_by_slug("cool-gadget")` stores the product under ID
  and a reference under slug
- Memory efficient: product stored once, slug key just points to it
- Eviction removes both the reference and the actual data

### Step 3: Category Management with Tagging

Add categories and use tags for organization:

```elixir
use Nebulex.Adapters.Local.QueryHelper

@decorate cacheable(
            key: category_id,
            opts: [ttl: @ttl, tag: "category:#{category_id}"]
          )
def get_products_by_category(category_id) do
  Repo.all(from p in Product, where: p.category_id == ^category_id)
end

# When a category is updated, invalidate all products in that category
@decorate cache_evict(query: &query_for_category/1)
def update_category_status(category_id, status) do
  # Update all products in this category
  Products.update_all_in_category(category_id, status: status)
end

defp query_for_category(%{args: [category_id, _status]}) do
  cat_tag = "category:#{category_id}"
  match_spec tag: t, where: t == ^cat_tag, select: true
end
```

### Step 4: Hierarchical Eviction with Combined Options

When deleting a category, evict both the category and all its products:

```elixir
use Nebulex.Adapters.Local.QueryHelper

@decorate cache_evict(
            key: category_id,
            query: &query_category_products/1
          )
def delete_category(category_id) do
  # Delete all products first
  Repo.delete_all(from p in Product, where: p.category_id == ^category_id)

  # Then delete the category
  Repo.delete(Category, category_id)
end

defp query_category_products(%{args: [category_id]}) do
  cat_tag = "category:#{category_id}"
  match_spec tag: t, where: t == ^cat_tag, select: true
end
```

**Execution flow:**
1. Query eviction removes all product entries with tag `"category:123"`
2. Key eviction removes the category entry with ID `123`
3. Function executes to update the database

### Step 5: User Sessions with Security

Use sessions with automatic expiration and proper cleanup:

```elixir
defmodule MyApp.Auth do
  use Nebulex.Caching,
    cache: MyApp.SessionCache,
    on_error: :nothing

  use Nebulex.Adapters.Local.QueryHelper

  @session_ttl :timer.hours(24)

  @decorate cacheable(
              key: session_id,
              opts: [ttl: @session_ttl, tag: "user:#{user_id}"]
            )
  def create_session(user_id) do
    session_id = generate_session_id()

    session = %{
      id: session_id,
      user_id: user_id,
      created_at: DateTime.utc_now()
    }

    {:ok, session}
  end

  # Logout: evict specific session and user's cache entry
  @decorate cache_evict(
              key: {:in, [session_id, user_id]},
              query: &query_user_session/1
            )
  def logout(session_id, user_id) do
    # Evicts:
    # 1. All entries tagged with this user (via query)
    # 2. The session_id and user_id keys
    Sessions.delete(session_id)
  end

  defp query_user_session(%{args: [_session_id, user_id]}) do
    user_tag = "user:#{user_id}"
    match_spec tag: t, where: t == ^user_tag, select: true
  end

  # Logout all sessions for a user
  @decorate cache_evict(query: &query_all_user_sessions/1)
  def logout_all_sessions(user_id) do
    Sessions.delete_all_for_user(user_id)
  end

  defp query_all_user_sessions(%{args: [user_id]}) do
    user_tag = "user:#{user_id}"
    match_spec tag: t, where: t == ^user_tag, select: true
  end
end
```

### Step 6: Advanced Search with Conditional Caching

Cache search results, but only for common queries:

```elixir
@decorate cacheable(
            key: &search_cache_key/1,
            match: &should_cache_search/1,
            opts: [ttl: :timer.minutes(15)]
          )
def search_products(params) do
  query =
    from p in Product,
      where: ilike(p.name, ^"%#{params.q}%"),
      limit: ^params.limit,
      offset: ^params.offset

  query
  |> maybe_filter_by_category(params[:category_id])
  |> maybe_filter_by_price_range(params[:min_price], params[:max_price])
  |> Repo.all()
end

defp search_cache_key(%{args: [params]}) do
  # Create a deterministic key from search parameters
  params
  |> Map.take([:q, :category_id, :min_price, :max_price, :limit, :offset])
  |> :erlang.phash2()
end

defp should_cache_search(results) do
  # Only cache if we got results and query wasn't too specific
  case results do
    [] -> false  # Don't cache empty results
    results when length(results) < 3 -> false  # Too specific
    results -> true  # Cache common searches
  end
end
```

### Step 7: Shopping Cart with References and TTL

Shopping carts can be accessed by cart ID or by user ID (assuming one cart
per user). Use references to avoid storing the same cart data twice:

```elixir
defmodule MyApp.Cart do
  use Nebulex.Caching,
    cache: MyApp.Cache,
    on_error: :nothing

  @cart_ttl :timer.hours(2)

  # Primary access by cart ID
  @decorate cacheable(key: cart_id, opts: [ttl: @cart_ttl])
  def get_cart(cart_id) do
    Repo.get(Cart, cart_id)
  end

  # Alternative access by user ID - stores reference to cart.id
  @decorate cacheable(
              key: user_id,
              references: &(&1 && &1.id),
              opts: [ttl: @cart_ttl]
            )
  def get_cart_by_user_id(user_id) do
    # Assuming user has only one active cart
    Repo.get_by(Cart, user_id: user_id)
  end

  @decorate cache_put(
              key: cart.id,
              match: &match_ok/1,
              opts: [ttl: @cart_ttl]
            )
  def add_item_to_cart(cart, product_id, quantity) do
    cart
    |> Cart.add_item(product_id, quantity)
    |> Repo.update()
  end

  # When checking out, evict both the cart.id and user_id keys
  @decorate cache_evict(key: {:in, [cart.id, cart.user_id]})
  def checkout(cart) do
    # Process checkout
    result = Orders.create_from_cart(cart)

    # Delete cart
    Repo.delete(cart)

    result
  end

  defp match_ok({:ok, cart}), do: {true, cart}
  defp match_ok(_), do: false
end
```

**How it works:**
- `get_cart(cart_id)` stores the cart under `cart.id`
- `get_cart_by_user_id(user_id)` stores a reference under `user_id`
  pointing to `cart.id`
- Both lookups return the same cached data (memory efficient)
- Eviction with `{:in, [cart.id, cart.user_id]}` removes both keys
- `keyref()` is NOT needed here since both keys are in the same cache

### Step 8: Admin Operations with Bulk Invalidation

Admin operations often require clearing large portions of the cache:

```elixir
defmodule MyApp.Admin do
  use Nebulex.Caching,
    cache: MyApp.Cache,
    on_error: :raise  # Raise errors for admin operations

  use Nebulex.Adapters.Local.QueryHelper

  # Refresh entire catalog (clear all product caches)
  @decorate cache_evict(
              query: fn _ -> match_spec(tag: t, where: t == :products) end
            )
  def refresh_catalog do
    # Evicts all entries tagged with :products
    ExternalAPI.sync_products()
  end

  # Update pricing (affects a specific category)
  @decorate cache_evict(query: &query_category_tag/1)
  def update_category_pricing(category_id, discount_percent) do
    Products.apply_discount_to_category(category_id, discount_percent)
  end

  defp query_category_tag(%{args: [category_id, _discount]}) do
    cat_tag = "category:#{category_id}"
    match_spec tag: t, where: t == ^cat_tag, select: true
  end

  # For multiple categories, iterate and evict each one
  def bulk_update_pricing(category_ids, discount_percent) do
    Enum.each(category_ids, fn cat_id ->
      update_category_pricing(cat_id, discount_percent)
    end)
  end

  # Nuclear option: clear everything
  @decorate cache_evict(all_entries: true, before_invocation: true)
  def clear_all_caches do
    # Cache cleared before function runs
    Logger.warning("All caches cleared by admin")
    :ok
  end
end
```

### Complete Example: Putting It All Together

Here's how these patterns work together in a typical request flow:

```elixir
defmodule MyApp.ProductController do
  use MyAppWeb, :controller

  def show(conn, %{"slug" => slug}) do
    # 1. Check cache by slug (might follow reference to ID)
    with {:ok, product} <- Catalog.get_product_by_slug(slug),
         # 2. Check if user has this in cart (cache hit if recent)
         {:ok, in_cart?} <-
           Cart.product_in_cart?(current_user_id(conn), product.id),
         # 3. Get related products (cached by category tag)
         {:ok, related} <-
           Catalog.get_products_by_category(product.category_id) do

      render(conn, "show.html",
        product: product,
        in_cart: in_cart?,
        related_products: related
      )
    end
  end

  def update(conn, %{"id" => id, "product" => params}) do
    # Update triggers cache_put, automatically refreshing cache
    with {:ok, product} <- Catalog.get_product(id),
         {:ok, updated} <- Catalog.update_product(product, params) do

      # If category changed, might need to invalidate category caches
      maybe_invalidate_category_cache(product, updated)

      json(conn, updated)
    end
  end

  def delete(conn, %{"id" => id}) do
    # Evicts both ID and slug keys, plus category tag cleanup
    with {:ok, product} <- Catalog.get_product(id),
         :ok <- Catalog.delete_product(product) do

      send_resp(conn, 204, "")
    end
  end
end
```

---

## Performance Considerations

### TTL Strategy

Choose TTL based on data volatility and consistency requirements:

```elixir
# High-churn data: short TTL
@decorate cacheable(key: id, opts: [ttl: :timer.minutes(5)])
def get_stock_price(symbol_id), do: # ...

# Stable data: long TTL
@decorate cacheable(key: id, opts: [ttl: :timer.hours(24)])
def get_product_category(id), do: # ...

# Static data: no expiration
@decorate cacheable(key: id)
def get_country_by_code(code), do: # ...
```

### Query Performance

Be mindful of query complexity, especially with large caches:

```elixir
use Nebulex.Adapters.Local.QueryHelper

# GOOD: Specific tag lookup (O(n) where n = entries with tag)
defp query_by_tag(%{args: [tag]}) do
  match_spec tag: t, where: t == ^tag, select: true
end

# CAREFUL: Value pattern matching (O(n) for all entries)
defp query_by_price_range(%{args: [min, max]}) do
  match_spec value: %{price: price},
             where: price >= ^min and price <= ^max,
             select: true
end
```

Consider denormalizing data or using more specific keys instead of
complex queries.

### Memory Management

Monitor cache size and implement eviction strategies:

```elixir
# Set max size at cache configuration
config :my_app, MyApp.Cache,
  adapter: Nebulex.Adapters.Local,
  gc_interval: :timer.hours(1),
  max_size: 100_000,
  allocated_memory: 2_000_000_000  # 2GB
```

Use tags to group and evict related entries efficiently:

```elixir
use Nebulex.Adapters.Local.QueryHelper

# Evict old sessions periodically
@decorate cache_evict(
            query: fn _ -> match_spec(tag: t, where: t == :sessions) end
          )
def cleanup_old_sessions do
  Sessions.delete_expired()
end
```

---

## Common Pitfalls and Troubleshooting

### Pitfall 1: Forgetting to Evict References

**Problem:**
```elixir
@decorate cache_evict(key: id)
def delete_user(id) do
  # Evicts user.id but not references (email, username, etc.)
  Repo.delete(User, id)
end
```

**Solution:**
```elixir
@decorate cache_evict(key: {:in, [user.id, user.email, user.username]})
def delete_user(user) do
  Repo.delete(user)
end
```

### Pitfall 2: Caching Errors

**Problem:**
```elixir
@decorate cacheable(key: id)
def get_user(id) do
  # If this returns {:error, :not_found}, it gets cached!
  Repo.get(User, id) || {:error, :not_found}
end
```

**Solution:**
```elixir
@decorate cacheable(
            key: id,
            match: &match_ok/1
          )
def get_user(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end

defp match_ok({:ok, _}), do: true
defp match_ok(_), do: false
```

### Pitfall 3: Inconsistent Cache Keys

**Problem:**
```elixir
# Different keys for same data
def get_user(id), do: Cache.get("user_#{id}")
def update_user(id, attrs), do: Cache.put("user:#{id}", ...)
```

**Solution:**
Use consistent key generation:

```elixir
@decorate cacheable(key: {:user, id})
def get_user(id), do: Repo.get(User, id)

@decorate cache_put(key: {:user, id})
def update_user(id, attrs), do: # ...
```

### Debugging Cache Issues

Enable telemetry logging to debug cache behavior:

```elixir
:telemetry.attach(
  "cache-debug",
  [:my_app, :cache, :command, :stop],
  fn event, measurements, metadata, _ ->
    IO.inspect({event, measurements.duration, metadata.command, metadata.result})
  end,
  nil
)
```

---

## Summary and Best Practices

### Key Takeaways

1. **Use the right decorator for the job:**
   - `@cacheable` for reads (cache-aside)
   - `@cache_put` for writes (always execute + cache)
   - `@cache_evict` for invalidation

2. **Leverage adapter-specific features:**
   - QueryHelper for readable queries
   - Tags for logical grouping
   - References to avoid duplication

3. **Design for eviction from the start:**
   - Plan your key structure
   - Use tags for related entries
   - Set appropriate TTLs

4. **Monitor and optimize:**
   - Use telemetry for observability
   - Watch memory usage
   - Profile query performance

### Recommended Reading

- [Cache Usage Patterns](http://hexdocs.pm/nebulex/3.0.0-rc.2/cache-usage-patterns.html)
  - Overview of caching patterns.
- [Nebulex.Caching.Decorators API](http://hexdocs.pm/nebulex/3.0.0-rc.2/Nebulex.Caching.Decorators.html)
  - Complete API reference.
- [Info API Guide](http://hexdocs.pm/nebulex/3.0.0-rc.2/info-api.html)
  - Monitoring and observability.
- [Nebulex.Adapters.Local Documentation](https://hexdocs.pm/nebulex_local)
  - Local adapter features.

---

Happy caching! 🚀
