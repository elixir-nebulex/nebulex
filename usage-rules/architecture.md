# Nebulex Architecture

This guide explains why Nebulex exists, who uses it, how it is structured
internally, and the non-negotiable design principles that govern every
contribution. Read the "Non-Negotiables" section at session start; read the
rest before structural changes.

This document describes the core package. In adapter repos, read "Why",
"Who", and "Key Design Decisions" for context; the Core Layer table and
Non-Negotiables #1, #3, #5, and #6 refer to the core repo, and the adapter's
own `AGENTS.md` or architecture doc governs layout, gate command, and upkeep
there (see "Scope" in `workflow.md`).

---

## Why Nebulex Exists

Elixir applications need caching. But caching backends — Redis, local ETS,
Memcached, Cachex, distributed cluster caches — each have their own APIs,
semantics, and failure modes. Without an abstraction layer, teams either
lock themselves into a single backend or scatter adapter-specific code
throughout their application.

Nebulex solves this the same way [Ecto][ecto] solved it for databases:
a **unified caching abstraction** that lets you swap backends, compose
topologies, and add declarative caching to any function — without changing
application code.

> "Give users explicit control over failure handling, while keeping the
> API ergonomic." — core design principle established in v3

Nebulex has been in production since 2017. It serves read-heavy workloads,
configuration caching, session management, and high-concurrency scenarios
across local, distributed, and hybrid cache setups.

[ecto]: https://github.com/elixir-ecto/ecto

---

## Who Uses It

Nebulex is used by Elixir teams who need:

- **Backend flexibility** — switch from a local ETS cache in development to
  Redis or a distributed cluster in production without changing application
  code.
- **Declarative caching** — annotate functions with `@decorate cacheable(...)`,
  `@decorate cache_put(...)`, or `@decorate cache_evict(...)` and let Nebulex
  handle the cache lifecycle automatically.
- **Composed topologies** — layer a local cache in front of a Redis cache, or
  run a coherent local cache with distributed invalidation, without writing
  topology-specific code.
- **Graceful degradation** — handle cache infrastructure failures (timeouts,
  connection drops, cluster failovers) differently from database failures,
  because a cache outage often permits fallback to the source of record.

---

## High-Level Architecture

Nebulex is organized into three distinct layers:

```ascii
+-------------------------------------------------------------+
|                     Application Layer                       |
|         (your modules using Nebulex.Cache API or            |
|          declarative caching decorators)                    |
+-------------------------------------------------------------+
                           |
+------------------------------------------------------------+
|                      Core Layer                            |
|                                                            |
|  +------------------+   +-------------------------------+  |
|  |  Nebulex.Cache   |<--|     Nebulex.Caching           |  |
|  |  (public API)    |   |  (declarative decorators)     |  |
|  +------------------+   +-------------------------------+  |
|            |                                               |
|            v                                               |
|  +-------------------------------------------------------+ |
|  |           Nebulex.Adapter behaviours                  | |
|  |  (KV, CompositeKV, Queryable, Transaction,            | |
|  |   Observable, Info)                                   | |
|  +-------------------------------------------------------+ |
+------------------------------------------------------------+
                           |
+------------------------------------------------------------+
|                     Adapter Layer                          |
|  (separate packages: nebulex_local, nebulex_distributed,   |
|   nebulex_redis_adapter, nebulex_adapters_cachex, etc.)    |
+------------------------------------------------------------+
```

### Core Layer — `lib/nebulex/`

The core package provides the abstraction. It contains no production cache
implementation; all storage logic lives in adapters.

| Module | Responsibility |
|---|---|
| `Nebulex.Cache` | Public API macro — `use Nebulex.Cache` generates the full cache API for a module |
| `Nebulex.Cache.KV` | Key-value operations: `fetch`, `get`, `put`, `delete`, `take`, etc. |
| `Nebulex.Cache.CompositeKV` | Composite KV operations (`get_and_update`, `update`, `fetch_or_store`, `get_or_store`), dispatched to the adapter's `Nebulex.Adapter.CompositeKV` callbacks |
| `Nebulex.Cache.Queryable` | Query-based operations: `get_all`, `count_all`, `delete_all` |
| `Nebulex.Cache.Transaction` | Transaction API wrappers (`transaction/2`, `in_transaction?/1`); locking semantics are adapter-defined (internal) |
| `Nebulex.Cache.Observable` | Event streaming for cache entry changes |
| `Nebulex.Cache.Info` | Stats and monitoring (`info/2`) |
| `Nebulex.Cache.Options` | NimbleOptions-based validation for all cache options; also exposes the shared runtime option names via `__runtime_shared_opts__/0` |
| `Nebulex.Cache.Supervisor` | OTP supervision tree for cache processes |
| `Nebulex.Cache.Registry` | Registry of running cache instances (name/pid to adapter meta), used for dynamic-cache lookup (internal) |
| `Nebulex.Cache.Helpers` | `defcacheapi` macro that generates the cache API functions (internal) |
| `Nebulex.Cache.QuerySpec` | NimbleOptions schema for query specs (internal) |
| `Nebulex.Adapter` | Adapter behaviour definition and shared macros |
| `Nebulex.Adapter.KV` | Callback spec for KV operations |
| `Nebulex.Adapter.CompositeKV` | Callback spec for composite KV operations (required) and their default implementation |
| `Nebulex.Adapter.Queryable` | Callback spec for query operations |
| `Nebulex.Adapter.Transaction` | Callback spec for transaction operations |
| `Nebulex.Adapter.Observable` | Callback spec for event streaming |
| `Nebulex.Adapter.Info` | Callback spec for stats/info |
| `Nebulex.Caching` | Entry point for declarative caching (`use Nebulex.Caching`) |
| `Nebulex.Caching.Decorators` | `cacheable`, `cache_put`, `cache_evict` decorator implementations |
| `Nebulex.Caching.Decorators.Runtime` | Runtime evaluation of cache operations, key generation, match logic |
| `Nebulex.Caching.Decorators.Context` | Per-invocation decorator context (function name, args, decorator type) |
| `Nebulex.Caching.Options` | NimbleOptions schemas for `use Nebulex.Caching` and decorator options (internal) |
| `Nebulex.Telemetry` | Telemetry span helpers used by cache commands (internal) |
| `Nebulex.Telemetry.CacheEntryHandler` | Telemetry handler that turns command events into cache entry events for Observable listeners |
| `Nebulex.Telemetry.CacheStatsCounterHandler` | Telemetry handler that aggregates stats via Erlang counters (backs `Nebulex.Adapters.Common.Info`) |
| `Nebulex.Event` | Shared event types (`t/0`, `listener/0`, `filter/0`) for the Observable API |
| `Nebulex.Event.CacheEntryEvent` | Cache entry event struct (`:inserted`, `:updated`, `:deleted`, `:expired`) |
| `Nebulex.Error`, `Nebulex.KeyError`, `Nebulex.CacheNotFoundError`, `Nebulex.QueryError` | Exceptions (`lib/nebulex/exceptions.ex`) |
| `Nebulex.Utils` | Shared helpers: `wrap_error/2`, `wrap_ok/1`, `unwrap_or_raise/1`, guards |
| `Nebulex.Time` | Time utilities for TTL and expiration |
| `Nebulex` | Top-level docs module |
| `Mix.Tasks.Nbx`, `Mix.Tasks.Nbx.Gen.Cache` | Mix task namespace and the `mix nbx.gen.cache` generator |

Modules with `@moduledoc false` are internal and not public API; that
includes the `Nebulex.Cache.*` feature modules behind `use Nebulex.Cache`,
`Nebulex.Caching.Decorators.Runtime`, and the ones marked "internal" above.
The public surface is `Nebulex.Cache`, `Nebulex.Caching`, `Nebulex.Adapter.*`,
`Nebulex.Adapters.*`, `Nebulex.Event.*`, the exceptions, `Nebulex.Utils`,
and `Nebulex.Time`.

### Adapter Layer — separate packages

Each adapter is its own Hex package. The core package ships only with
`Nebulex.Adapters.Nil` (a no-op adapter used for tests and for benchmarking
the abstraction layer itself) and the shared `Nebulex.Adapters.Common.Info`
(default `Nebulex.Adapter.Info` implementation) and
`Nebulex.Adapters.Common.Info.Stats` (stats helpers) modules.

For the canonical list of official adapters (package names, modules,
and Hex/GitHub links), see `guides/introduction/nbx-adapters.md`. That
guide is the single source of truth — do not maintain a parallel list here.

### Declarative Caching — `Nebulex.Caching`

Declarative caching is built on the [`decorator`][decorator-lib] library.
`use Nebulex.Caching` registers three function decorators:

- `cacheable` — read-through: skip execution on cache hit, populate on miss
- `cache_put` — write-through: always execute, always update the cache
- `cache_evict` — invalidation: execute and remove entries from the cache

The decorator macro captures key expressions and option lambdas as AST at
compile time and inlines them into generated wrapper functions. All runtime
resolution (key generation, cache selection, match evaluation) happens in
Nebulex.Caching.Decorators.Runtime.

[decorator-lib]: https://github.com/arjan/decorator

---

## Key Design Decisions

### ok/error tuples everywhere

All cache operations return `{:ok, value}` or `{:error, reason}` by default.
Bang variants (`fetch!/2`, `put!/3`, etc.) are available for fail-fast
semantics. This was a deliberate v3 decision: cache infrastructure failures
should be handled explicitly at each call site, not swallowed silently.

### Adapters are decoupled — always

The core package has no runtime dependency on any adapter package. Adapters
depend on core, never the reverse. The adapter callback specs (`Nebulex.Adapter.*`)
define the contract; the core enforces it at compile time via behaviours.

This decoupling means adapters evolve independently. A breaking change in an
adapter does not require a core release. New adapters can be published by
anyone without touching the core repository.

### Minimal, mostly optional dependencies

The only required runtime dependency is `:nimble_options`. `:telemetry`,
`:decorator`, and all adapters are optional. This keeps the core footprint
minimal for users who only need a subset of features. If an optional
dependency is absent, the feature it enables is simply unavailable (no
runtime error, no silent failure). Adding a new required dependency is an
architectural change; see Non-Negotiable #6.

### NimbleOptions for all option validation

Every public option set — cache options, decorator options, adapter-specific
options — is validated through [NimbleOptions][nimble_options] schemas. This
produces consistent, actionable error messages at compile time or startup,
rather than cryptic runtime failures.

[nimble_options]: https://hexdocs.pm/nimble_options

### Telemetry as the observability contract

The core emits a Telemetry span (`:start`, `:stop`, `:exception`) for every
cache command, regardless of which adapter is in use. The event name is
`telemetry_prefix ++ [:command]`, where `:telemetry_prefix` defaults to the
cache module name split into atoms (`MyApp.Cache` becomes
`[:my_app, :cache]`). The metadata always includes `:adapter_meta`,
`:command`, `:args`, and `:extra_metadata`; the stop event adds `:result`.
The only fixed-name event is `[:nebulex, :cache, :init]`, emitted when a
cache starts. Adapters may emit additional events but must not suppress or
redefine core events. This guarantees that monitoring dashboards and
telemetry handlers work across backend switches. See
`Nebulex.Adapter.run_command/4` for command spans and
`Nebulex.Cache.Supervisor` for the init event.

### Nil is a valid cache value

Since v3, `nil` can be cached. The sentinel-value restriction from v2 (where
`nil` meant "cache miss") is gone. Match functions control whether a result
is cached, giving developers explicit control over nil caching.

---

## Non-Negotiables

These rules are not open for debate. Any contribution that violates them
will not be merged, regardless of other merits.

### 1. Adapters must remain decoupled from core

The core package must not import, alias, or depend on any adapter module at
runtime. Shared utilities belong in `Nebulex.Adapters.Common.*` within the
core, not in adapter packages. If you find yourself adding an adapter-specific
module to the core, stop and reconsider. In an adapter repo the same rule
reads: never edit `deps/nebulex/`; propose the change in the core repo.

### 2. No breaking public API changes without a major version

`Nebulex.Cache`, `Nebulex.Caching`, and all `Nebulex.Adapter.*` callback specs
are public API. Removing or renaming public functions, changing callback
signatures, or altering option semantics requires a major version bump
(`v3.x` → `v4.0`). Deprecation warnings must precede removals by at least
one minor release.

### 3. Every public function must have a `@doc` and typespec

Module documentation (`@moduledoc`) is required for every module. Public
functions require `@doc` and `@spec`. In core, `mix doctor` enforces 100%
`@moduledoc` and at least 80% `@doc` coverage (`.doctor.exs`); `@spec` and
the remaining `@doc` coverage are enforced in review. Undocumented public
API will not be merged.

### 4. New behaviour must have tests

Any new feature, option, or code path must be accompanied by tests. For
adapter-facing changes, tests belong in `test/shared/` using the `deftests`
macro so the shared test suite covers all adapters consistently. A shared
behavioural test is a contract every adapter must satisfy; for behaviour
adapters may legitimately not support, test it in `test/nebulex/` against
`Nebulex.TestAdapter` instead. For core-only changes, tests belong in
`test/nebulex/`. A PR without tests for new behaviour will not be merged.

### 5. The canonical gate must pass

Authors run the repo's gate alias before opening a PR; reviewers rely on
green CI:

```bash
mix precommit
```

`workflow.md` ("Canonical Gate") lists exactly what the core alias runs.
Green CI on the PR is a requirement, not a courtesy check.

### 6. Keep this document up to date

After any structural change — new module, new adapter callback, new
dependency, a new option that changes the adapter contract, or changes to
the layer boundaries — review the architecture doc of the repo you are in
and update it if needed. Architecture docs rot when nobody owns them. This
is not a checkbox on every PR, but a conscious check: "did my change affect
the architecture described here?"

### 7. `mix docs` must produce no warnings

Documentation must build cleanly:

```bash
mix docs
```

No warnings are acceptable. Common causes: referencing hidden modules with
backtick syntax, broken links, or missing `@doc`/`@moduledoc`. Fix the root
cause — do not suppress warnings.

---

## Source of Truth Hierarchy

When in doubt about intent, consult these sources in order:

1. `workflow.md` — contribution workflow and rule precedence
2. This document — architectural decisions and non-negotiables
3. `nebulex.md` — domain-specific patterns and pitfalls
4. Module `@moduledoc` and function `@doc` — local intent for each API
5. `CHANGELOG.md` — history of decisions and the reasoning behind them
6. The blog post ["Nebulex v3: A New Chapter for Caching in Elixir"][v3-post]
   for the philosophy behind the v3 redesign

[v3-post]: https://medium.com/erlang-battleground/nebulex-v3-a-new-chapter-for-caching-in-elixir-03cd366692c3
