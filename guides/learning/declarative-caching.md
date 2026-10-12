# Declarative Caching: Patterns and Best Practices

This guide shows how to use Nebulex's caching decorators in a real
application. The `Nebulex.Caching.Decorators` documentation covers every
option and the basic usage; this guide covers common scenarios,
adapter-specific features, and the patterns that go beyond the basics.

---

## Introduction

Nebulex provides three main decorators for implementing declarative caching:

- **`@decorate cacheable`** - Read-through caching (cache-aside pattern)
- **`@decorate cache_put`** - Write-through caching (always execute
  and cache result)
- **`@decorate cache_evict`** - Cache invalidation (remove entries)

The decorators make the cache calls for you, so the function body holds
only your own logic.

### Setup

Caching decorators require the `:decorator` dependency. Add it to your
`mix.exs`:

```elixir
{:decorator, "~> 1.4"}
```

Then enable caching decorators in your module:

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
- `:default_key_generator` - Default key generation function
- `:on_error` - How to handle cache errors (`:nothing` or `:raise`)
- `:transaction` - Whether to run the function and cache operations in a
  transaction
- `:match` - Default match function for conditional caching
- `:opts` - Default options passed to cache operations (e.g., TTL)

---

## Quick Start: Basic Usage

Let's start with a simple product catalog to illustrate the basics. For complete
API documentation on all three decorators, see `Nebulex.Caching.Decorators`.

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
@decorate cache_evict(key: product.id)
def delete_product(product) do
  Repo.delete(product)
end
```

**How it works:**
1. Function executes
2. After successful execution, the cache entry is removed

---

## Advanced Eviction Patterns

The `cache_evict` decorator supports several ways to invalidate entries.
For the option reference, see
[`cache_evict/3`](`Nebulex.Caching.Decorators.cache_evict/3`).

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

You can use both `:key` and `:query` together for hierarchical eviction:

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

The `Nebulex.Adapters.Local` adapter has features that make queries, entry
grouping, and reference cleanup easier. This section covers them.

For complete API documentation, see the
["Local Adapter: Advanced Reference Eviction"](`m:Nebulex.Caching.Decorators#cache_evict/3-local-adapter-advanced-reference-eviction`)
section in `cache_evict/3`.

### Building Queries with QueryHelper

The `Nebulex.Adapters.Local.QueryHelper` module lets you build ETS match
specifications without writing the raw tuples.

> #### New in `Nebulex.Adapters.Local` v3.0.0 {: .tip}
>
> See the [QueryHelper documentation][query_helper_docs] for the full
> syntax.

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

**With QueryHelper:**

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

Tags let you group cache entries so you can evict them together.

> #### New in `Nebulex.Adapters.Local` v3.0.0 {: .tip}
>
> See the [Local adapter documentation][local_adapter_docs] for details.

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

Cache references let you store a value once and point to it from other
keys, so the same value is not stored twice.

> #### New in `Nebulex.Adapters.Local` v3.0.0 {: .tip}
>
> See ["Building Match Specs with QueryHelper"][query_helper_section]
> for details.

[query_helper_section]: https://hexdocs.pm/nebulex_local/Nebulex.Adapters.Local.html#module-building-match-specs-with-queryhelper

For complete API documentation on the `:references` option, see
[`cacheable/3` - Referenced keys](`m:Nebulex.Caching.Decorators#cacheable/3-referenced-keys`).

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
- Matches references in any cache, or only those pointing at a key in the
  cache given with `cache:`
- Automatically handles the internal reference structure
- Returns a match spec you can use with `cache_evict`

For advanced reference management, see
["Building Match Specs with QueryHelper"][query_helper_section].

**Using TTL to automatically expire references:**

```elixir
@decorate cacheable(
            key: email,
            references: &(&1 && keyref(&1.id, ttl: :timer.hours(24))),
            opts: [ttl: :timer.hours(1)]
          )
def get_user_by_email(email) do
  Repo.get_by(User, email: email)
end
```

The decorator's `:opts` TTL applies to the reference stored under `email`, so
it expires after one hour. The `ttl:` given to `keyref/2` applies to the
referenced entry under `user.id` instead, so the user record lives for 24
hours. Expiring references keeps them from pointing at stale or missing
values forever. The `&1 &&` guard matters: the references function runs on
the raw result before `:match`, so it must handle `nil`.

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
            references: &(&1 && keyref(&1.id, cache: UserCache))
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
- This is the case where you need `keyref()`: cross-cache eviction

### Advanced Reference Cleanup with Tags and Queries

When several keys point to the same value, listing every reference in
`cache_evict` gets tedious. The `Nebulex.Adapters.Local` adapter gives you
two ways to clean up all references without naming each one.

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
- One query evicts everything
- Works well when you control how references are created

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

**Why this works:**
- Discovers references automatically
- Works even if references are created conditionally
- Handles references created by different decorators
- Needs no tag planning

**Trade-offs:**
- Slightly more complex than tag-based approach
- Query performs a scan to find references

#### Choosing Between Strategies

| Strategy | Best For | Tradeoff |
|----------|----------|----------|
| **Tags** | Coordinated cleanup, related entries | Requires upfront planning |
| **keyref_match_spec** | Multiple access patterns, flexibility | Slight performance cost for query |
| **Combined** | Covers both cases | Most setup |

**Recommended approach for production:**

Use a tag for group cleanup and `keyref_match_spec` for single-user cleanup.
A tag is set when the entry is written, so it can only come from the
function arguments or a constant; a lookup by email cannot tag its entry
with the user ID. A static group tag still lets you clear the whole group at
once:

```elixir
use Nebulex.Adapters.Local.QueryHelper

@decorate cacheable(key: id, opts: [tag: :users])
def get_user(id) do
  Repo.get(User, id)
end

@decorate cacheable(
            key: email,
            references: &(&1 && &1.id),
            opts: [tag: :users]
          )
def get_user_by_email(email) do
  Repo.get_by(User, email: email)
end

@decorate cacheable(
            key: username,
            references: &(&1 && &1.id),
            opts: [tag: :users]
          )
def get_user_by_username(username) do
  Repo.get_by(User, username: username)
end

# Group cleanup: evict every user entry and every reference in one query
@decorate cache_evict(query: &evict_all_users/1)
def reload_users do
  Users.reload_from_source()
end

defp evict_all_users(_context) do
  match_spec tag: t, where: t == :users, select: true
end

# Single user: evict the user entry by key and its references by query
@decorate cache_evict(key: user.id, query: &evict_user_refs/1)
def delete_user(user) do
  Repo.delete(user)
end

defp evict_user_refs(%{args: [user]}) do
  keyref_match_spec(user.id)
end
```

The tag handles the bulk case and `keyref_match_spec` handles the per-user
case, so no reference is left dangling on either path.

---

## Example: An E-commerce Product Catalog

This example starts with simple caching and adds patterns step by step, so
you can see how the features fit together.

### The Scenario

We're building an e-commerce platform with:
- Products organized in categories
- User sessions and authentication
- Product search and filtering
- Shopping carts
- Administrative operations

We'll add caching step by step.

### Step 1: Basic Product Caching

Start with simple read-through caching for products. Every function returns
an ok/error tuple, so callers can chain them with `with`, and the cache
stores the `{:ok, product}` tuple as is. The default `:match` skips `nil`,
`:error`, and `{:error, _}`, so a missing product is never cached. Entries
are tagged `:products` (a `Nebulex.Adapters.Local` put option) so Step 8 can
evict them all at once:

```elixir
defmodule MyApp.Catalog do
  use Nebulex.Caching,
    cache: MyApp.Cache,
    on_error: :nothing

  alias MyApp.Repo
  alias MyApp.Catalog.Product

  @ttl :timer.hours(2)

  @decorate cacheable(key: id, opts: [ttl: @ttl, tag: :products])
  def fetch_product(id) do
    case Repo.get(Product, id) do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  @decorate cache_put(
              key: product.id,
              match: &match_ok/1,
              opts: [ttl: @ttl, tag: :products]
            )
  def update_product(product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  @decorate cache_evict(key: product.id)
  def delete_product(product) do
    Repo.delete(product)
  end

  # Cache the whole `{:ok, product}` tuple so a cache hit returns the same
  # shape as a cache miss
  defp match_ok({:ok, _product}), do: true
  defp match_ok(_), do: false
end
```

### Step 2: Multiple Access Patterns with References

Products can be accessed by ID or slug. Use references to avoid duplication.
The `:references` function receives the function result, so it has to unwrap
the tuple; returning `nil` skips the cache, which is what we want for
`{:error, :not_found}`:

```elixir
@decorate cacheable(key: id, opts: [ttl: @ttl, tag: :products])
def fetch_product(id) do
  case Repo.get(Product, id) do
    nil -> {:error, :not_found}
    product -> {:ok, product}
  end
end

@decorate cacheable(
            key: slug,
            references: &product_ref/1,
            opts: [ttl: @ttl, tag: :products]
          )
def fetch_product_by_slug(slug) do
  case Repo.get_by(Product, slug: slug) do
    nil -> {:error, :not_found}
    product -> {:ok, product}
  end
end

# When evicting, remove both keys
@decorate cache_evict(key: {:in, [product.id, product.slug]})
def delete_product(product) do
  Repo.delete(product)
end

defp product_ref({:ok, product}), do: product.id
defp product_ref(_), do: nil
```

**What happens:**
- `fetch_product_by_slug("cool-gadget")` stores `{:ok, product}` under the
  ID and a reference under the slug
- Memory efficient: the product is stored once, the slug key just points to
  it
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
  Category |> Repo.get!(category_id) |> Repo.delete()
end

defp query_category_products(%{args: [category_id]}) do
  cat_tag = "category:#{category_id}"
  match_spec tag: t, where: t == ^cat_tag, select: true
end
```

**Execution flow:**
1. The function runs and updates the database
2. Query eviction removes all product entries with tag `"category:123"`
3. Key eviction removes the category entry with ID `123`

### Step 5: User Sessions

Sessions expire on their own and are cleaned up on logout:

```elixir
defmodule MyApp.Auth do
  use Nebulex.Caching,
    cache: MyApp.SessionCache,
    on_error: :nothing

  use Nebulex.Adapters.Local.QueryHelper

  @session_ttl :timer.hours(24)

  @decorate cacheable(
              key: user_id,
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

  # Logout: evict the user's session entry
  @decorate cache_evict(
              key: user_id,
              query: &query_user_session/1
            )
  def logout(session_id, user_id) do
    # Evicts:
    # 1. All entries tagged with this user (via query)
    # 2. The user_id key, where create_session/1 stored the session
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
  def fetch_cart(cart_id) do
    case Repo.get(Cart, cart_id) do
      nil -> {:error, :not_found}
      cart -> {:ok, cart}
    end
  end

  # Alternative access by user ID - stores reference to cart.id
  @decorate cacheable(
              key: user_id,
              references: &cart_ref/1,
              opts: [ttl: @cart_ttl]
            )
  def fetch_cart_by_user_id(user_id) do
    # Assuming user has only one active cart
    case Repo.get_by(Cart, user_id: user_id) do
      nil -> {:error, :not_found}
      cart -> {:ok, cart}
    end
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

  defp cart_ref({:ok, cart}), do: cart.id
  defp cart_ref(_), do: nil

  defp match_ok({:ok, _cart}), do: true
  defp match_ok(_), do: false
end
```

**How it works:**
- `fetch_cart(cart_id)` stores `{:ok, cart}` under `cart.id`
- `fetch_cart_by_user_id(user_id)` stores a reference under `user_id`
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

  require Logger

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

  # Clear everything
  @decorate cache_evict(all_entries: true, before_invocation: true)
  def clear_all_caches do
    # Cache cleared before function runs
    Logger.warning("All caches cleared by admin")
    :ok
  end
end
```

### Putting It All Together

Here's how these patterns work together in a typical request flow. Because
every `Catalog` fetch function returns an ok/error tuple, the controller can
chain them with `with` and let a `{:error, :not_found}` fall through to the
error handling:

```elixir
defmodule MyApp.ProductController do
  use MyAppWeb, :controller

  alias MyApp.Catalog

  def show(conn, %{"slug" => slug}) do
    # Cached by slug (follows the reference to the product ID)
    with {:ok, product} <- Catalog.fetch_product_by_slug(slug) do
      # Cached by category tag
      related = Catalog.get_products_by_category(product.category_id)

      render(conn, "show.html", product: product, related_products: related)
    end
  end

  def update(conn, %{"id" => id, "product" => params}) do
    # cache_put refreshes the cached product on success
    with {:ok, product} <- Catalog.fetch_product(id),
         {:ok, updated} <- Catalog.update_product(product, params) do
      # If the category changed, the category entries may need eviction too
      maybe_invalidate_category_cache(product, updated)

      json(conn, updated)
    end
  end

  def delete(conn, %{"id" => id}) do
    # Evicts both the ID and slug keys
    with {:ok, product} <- Catalog.fetch_product(id),
         {:ok, _deleted} <- Catalog.delete_product(product) do
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
@decorate cacheable(key: symbol_id, opts: [ttl: :timer.minutes(5)])
def get_stock_price(symbol_id) do
  # ...
end

# Stable data: long TTL
@decorate cacheable(key: id, opts: [ttl: :timer.hours(24)])
def get_product_category(id) do
  # ...
end

# Static data: no expiration
@decorate cacheable(key: code)
def get_country_by_code(code) do
  # ...
end
```

### Query Performance

Be mindful of query complexity, especially with large caches:

```elixir
use Nebulex.Adapters.Local.QueryHelper

# Both queries scan the whole table. Comparing the tag is cheap per entry;
# matching inside the value is more work per entry.
defp query_by_tag(%{args: [tag]}) do
  match_spec tag: t, where: t == ^tag, select: true
end

# Value pattern matching: more work per entry
defp query_by_price_range(%{args: [min, max]}) do
  match_spec value: %{price: price},
             where: price >= ^min and price <= ^max,
             select: true
end
```

Consider denormalizing data or using more specific keys instead of
complex queries.

### Memory Management

Set limits on the cache size:

```elixir
# Set max size at cache configuration
config :my_app, MyApp.Cache,
  adapter: Nebulex.Adapters.Local,
  gc_interval: :timer.hours(1),
  max_size: 100_000,
  allocated_memory: 2_000_000_000  # 2GB
```

Use tags to group and evict related entries:

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
  User |> Repo.get!(id) |> Repo.delete()
end
```

**Solution:**
```elixir
@decorate cache_evict(key: {:in, [user.id, user.email, user.username]})
def delete_user(user) do
  Repo.delete(user)
end
```

### Pitfall 2: Caching Failed Results

The default match function skips `nil`, `:error`, and `{:error, _}` results
and caches anything else. A result that encodes failure in any other shape
is cached like a success.

**Problem:**
```elixir
@decorate cacheable(key: id)
def fetch_user(id) do
  # `:not_found` is cached, so the lookup never reaches the database again
  # until the entry expires
  Repo.get(User, id) || :not_found
end
```

**Solution:** return ok/error tuples and let the default match do the rest:
```elixir
@decorate cacheable(key: id)
def fetch_user(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end
```

If you cannot change the result shape, use `:match` to say what counts as a
success:
```elixir
@decorate cacheable(key: id, match: &match_found/1)
def fetch_user(id) do
  Repo.get(User, id) || :not_found
end

defp match_found(:not_found), do: false
defp match_found(_user), do: true
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
def update_user(id, attrs) do
  # ...
end
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

2. **Use adapter-specific features:**
   - QueryHelper for readable queries
   - Tags for logical grouping
   - References to avoid duplication

3. **Design for eviction from the start:**
   - Plan your key structure
   - Use tags for related entries
   - Set appropriate TTLs

4. **Monitor and optimize:**
   - Use telemetry to see what the cache is doing
   - Watch memory usage
   - Profile query performance

### Recommended Reading

- [Cache Usage Patterns](cache-usage-patterns.md) – Overview of caching patterns.
- [Nebulex.Caching.Decorators API](`Nebulex.Caching.Decorators`) – Complete API reference.
- [Info API Guide](info-api.md) – Monitoring and observability.
- [Nebulex.Adapters.Local Documentation](https://hexdocs.pm/nebulex_local) – Local adapter features.
