# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v3.0.0-rc.2](https://github.com/elixir-nebulex/nebulex/tree/v3.0.0-rc.2) (2025-12-07)
> [Full Changelog](https://github.com/elixir-nebulex/nebulex/compare/v3.0.0-rc.1...v3.0.0-rc.2)

### Enhancements

- [Nebulex.Cache] Added `:telemetry` option as a shared command option,
  allowing selective override of the global telemetry setting on a per-command
  basis without needing to start separate cache instances.
- [Nebulex.Cache] Added `fetch_or_store` callback to the Cache API.
  For more information, see:
  [#240](https://github.com/elixir-nebulex/nebulex/issues/240).
- [Nebulex.Cache] Added `get_or_store` callback to the Cache API.
  For more information, see:
  [#241](https://github.com/elixir-nebulex/nebulex/issues/241).
- [Nebulex.Caching.Decorators] The `cache_evict` decorator now supports a
  `:query` option for bulk eviction based on adapter-specific queries.
  For example: `@decorate cache_evict(query: my_query)`. The query can be
  provided directly or as a function that returns the query at runtime.
  Additionally, both `:query` and `:key` options can be used together to
  evict specific entries and entries matching a query pattern in a single
  operation. When both are provided, query-based eviction executes first,
  followed by key-based eviction.
  For more information, see:
  [#243](https://github.com/elixir-nebulex/nebulex/issues/243).
  [#245](https://github.com/elixir-nebulex/nebulex/issues/245).
- [Nebulex.Caching.Decorator] Add support for evicting external references in
  `cache_evict` decorator. For more information, see:
  [#244](https://github.com/elixir-nebulex/nebulex/issues/244)
- [Documentation] Added comprehensive "Declarative Caching" guide
  (`guides/learning/declarative-caching.md`) showcasing patterns, best
  practices, and real-world examples for using caching decorators. The guide
  includes progressive learning with an e-commerce scenario covering basic
  decorator usage, advanced eviction patterns (including the new combined
  `:key` and `:query` feature), `Nebulex.Adapters.Local` features
  (QueryHelper, tagging, references), testing strategies, and common pitfalls.
  Replaces ad-hoc examples previously scattered in API documentation.
  [#246](https://github.com/elixir-nebulex/nebulex/issues/246).

## [v3.0.0-rc.1](https://github.com/elixir-nebulex/nebulex/tree/v3.0.0-rc.1) (2025-05-01)
> [Full Changelog](https://github.com/elixir-nebulex/nebulex/compare/v2.6.4...v3.0.0-rc.1)

### Enhancements

- [Nebulex.Cache] New ok/error tuple API for all cache functions.
- [Nebulex.Cache] Alternative cache trailing bang (`!`) functions.
- [Nebulex.Cache] All cache commands (in addition to `c:get_dynamic_cache/0`,
  `c:put_dynamic_cache/1`, and `c:with_dynamic_cache/2`) optionally support
  passing the desired dynamic cache (name or PID) as the first argument to
  interact directly with a cache instance.
- [Nebulex.Cache] A ["Query Spec"][q_spec] has been added and must be used for
  all Query API calls.
- [Nebulex.Cache] Added fetch callbacks: `c:Nebulex.Cache.fetch/2,3` and
  `c:Nebulex.Cache.fetch!/2,3`.
- [Nebulex.Cache] `c:Nebulex.Cache.get/3` semantics changed a bit. Previously,
  returned `nil` when the given key wasn't in the cache. Now, the callback
  accepts an argument to specify the default value when the key is not found
  (defaults to `nil`).
- [Nebulex.Cache] Any Elixir term, including `nil`, can be stored in the cache.
  Any meaning or semantics behind `nil` (or any other term) is up to the user.
- [Nebulex.Cache] `Nebulex.Cache` now emits Telemetry span events for each cache
  command (without depending on the adapters).
- [Nebulex.Cache] Option `:bypass_mode` has been added to
  `c:Nebulex.Cache.start_link/1` for bypassing the cache by overwriting the
  configured adapter with `Nebulex.Adapters.Nil` when the cache starts. This
  option is handy for tests if you want to disable or bypass the cache while
  running them.
- [Nebulex.Cache] Added "Info API" to get information about the cache.
  For example: memory, stats, etc.
- [Nebulex.Cache] Added "Observable" API to maintain a registry of listeners
  and invoke them to handle cache events.
- [Nebulex.Caching.Decorators] Option `:cache` supports a cache module,
  a dynamic cache, and an anonymous function to resolve the cache at runtime.
- [Nebulex.Caching.Decorators] Option `:key`, in addition to a compilation-time
  term, supports a tuple `{:in, keys}` to specify a list of keys, and an
  anonymous function to resolve the key at runtime.
- [Nebulex.Caching.Decorators] Option `:references` supports dynamic caches.
- [Nebulex.Caching.Decorators] Option `:references` can now receive a TTL.
  (e.g., `references: &keyref(&1.id, ttl: :timer.seconds(10))`).
- [Nebulex.Caching.Decorators] Handle possible inconsistencies when using
  references, leveraging the match function. See
  ["match function on references"][match_ref] for more information.
- [Nebulex.Caching] The following option can be provided when using
  `use Nebulex.Caching` (instead of adding them to every single decorated
  function): `:cache`, `:on_error`, `:match`, and `:opts`.

[q_spec]: http://hexdocs.pm/nebulex/3.0.0-rc.1/Nebulex.Cache.html#c:get_all/2-query-specification
[match_ref]: http://hexdocs.pm/nebulex/3.0.0-rc.1/Nebulex.Caching.Decorators.html#cacheable/3-the-match-function-on-references

### Backwards incompatible changes

- [Nebulex.Cache] `c:Nebulex.Cache.all/2` has been removed. Please use
  `c:Nebulex.Cache.get_all/2` instead
  (e.g., `MyCache.get_all(query: query_supported_by_the_adapter)`).
- [Nebulex.Cache] `c:Nebulex.Cache.get_all/2` belongs to the Query API and
  receives a ["query spec"][q_spec] (e.g., `MyCache.get_all(in: [...])`).
- [Nebulex.Caching.Decorators] The `:cache` option doesn't support MFA tuples
  anymore. Please use an anonymous function instead
  (e.g., `cache: &MyApp.Caching.get_cache/1`).
- [Nebulex.Caching.Decorators] Option `:keys` is no longer supported. Please use
  the option `:key` instead (e.g., `key: {:in, keys}`).
- [Nebulex.Caching.Decorators] Option `:key_generator` is no longer supported on
  the decorators. Please use the option `:key` instead
  (e.g., `key: &MyApp.Caching.compute_key/1`).
- [Nebulex.Caching] The `Nebulex.Caching.KeyGenerator` behaviour has been
  removed. Please use the `:default_key_generator` option with an anonymous
  function instead (must be provided in the format `&Mod.fun/arity`). Besides,
  the `:default_key_generator` option must be provided to `use Nebulex.Caching`.
  (e.g., `use Nebulex.Caching, default_key_generator: &MyApp.generate_key/1`).
- [Nebulex.Adapter.Stats] `Nebulex.Adapter.Stats` behaviour has been removed.
  Therefore, `c:Nebulex.Cache.stats/0` and `c:Nebulex.Cache.dispatch_stats/1`
  are no longer supported. Please use `Nebulex.Adapter.Info` instead.
- [Nebulex.Adapter.Persistence] `Nebulex.Adapter.Persistence` behaviour has been
  removed. Therefore, `c:Nebulex.Cache.dump/2` and `c:Nebulex.Cache.load/2`
  are no longer supported.

### Adapter changes

- [Nebulex.Adapter.Info] `Nebulex.Adapter.Info` adapter behaviour has been added
  to handle cache information and stats (optional).
- [Nebulex.Adapter.Observable] `Nebulex.Adapter.Observable` adapter behaviour
  has been added to maintain a registry of listeners and invoke them to handle
  cache events (optional).
- [Nebulex.Adapters.Local] The adapter `Nebulex.Adapters.Local` has been moved
  to a separate [repository](https://github.com/elixir-nebulex/nebulex_local).
- [Nebulex.Adapters.Partitioned] The adapter `Nebulex.Adapters.Partitioned`
  has been moved to a separate
  [repository](https://github.com/elixir-nebulex/nebulex_distributed).
- [Nebulex.Adapters.Multilevel] The adapter `Nebulex.Adapters.Multilevel`
  has been moved to a separate
  [repository](https://github.com/elixir-nebulex/nebulex_distributed).
- [Nebulex.Adapters.Replicated] The adapter `Nebulex.Adapters.Replicated`
  has been moved to a separate
  [repository](https://github.com/elixir-nebulex/nebulex_distributed) (WIP).

### Closed issues

- Nebulex `v3.0.0-rc.1` roadmap
  [#189](https://github.com/elixir-nebulex/nebulex/issues/189)

## Previous versions

  * See the CHANGELOG.md [in the v2 branch](https://github.com/elixir-nebulex/nebulex/blob/v2/CHANGELOG.md)
