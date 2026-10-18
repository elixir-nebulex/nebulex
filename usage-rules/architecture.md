# Nebulex Architecture

This guide covers what the code and the module docs do not: the boundaries
between the layers, the design decisions behind them, and the non-negotiable
rules for every change. Read the "Non-Negotiables" section at session start;
read the rest before structural changes.

This document describes the core package. In adapter repos, read "Purpose",
"Boundaries", and "Design Decisions" for context; the adapter's own
`AGENTS.md` or architecture doc governs its layout, gate command, and upkeep
(see "Scope" in `workflow.md`).

---

## Purpose

Nebulex is a caching abstraction for Elixir, in the spirit of Ecto for
databases: one `Nebulex.Cache` API and a set of `Nebulex.Adapter.*`
behaviours, so applications can swap backends, compose topologies, and add
declarative caching without changing application code. The core package
ships no production cache; storage lives in adapter packages. The user-facing
story is in `guides/` (<https://hexdocs.pm/nebulex>); do not repeat it here.

---

## Boundaries

Three layers: the application (modules that call the cache API or use the
decorators), the core (this package), and the adapters (separate packages).

The core provides:

- `Nebulex.Cache`: `use Nebulex.Cache` generates the cache API. The feature
  modules behind it live in `lib/nebulex/cache/` (`KV`, `CompositeKV`,
  `Queryable`, `Transaction`, `Observable`, `Info`, plus `Options`,
  `Supervisor`, `Registry`, `Helpers`, `QuerySpec`) and are internal.
- `Nebulex.Adapter` and `Nebulex.Adapter.<Feature>` in `lib/nebulex/adapter/`:
  the behaviours adapters implement. `Nebulex.Adapter`, `KV`, and
  `CompositeKV` are required; `Queryable`, `Transaction`, `Observable`, and
  `Info` are optional.
- `Nebulex.Caching` and `lib/nebulex/caching/`: the `cacheable`, `cache_put`,
  and `cache_evict` decorators, built on the `decorator` library. The macro
  captures key expressions and option lambdas as AST at compile time; all
  runtime resolution happens in `Nebulex.Caching.Decorators.Runtime`.
- `Nebulex.Telemetry` and its handlers, `Nebulex.Event.*`, the exceptions
  (`lib/nebulex/exceptions.ex`), `Nebulex.Utils`, and `Nebulex.Time`.
- `Nebulex.Adapters.Nil` (a no-op adapter used for tests and for
  benchmarking the abstraction) and `Nebulex.Adapters.Common.Info` (the
  default `Nebulex.Adapter.Info` implementation): the only adapter code in
  core.
- `mix nbx.gen.cache` in `lib/mix/tasks/`, the only generator.

The public surface is `Nebulex.Cache`, `Nebulex.Caching`, `Nebulex.Adapter.*`,
`Nebulex.Adapters.*`, `Nebulex.Event.*`, the exceptions, `Nebulex.Utils`,
and `Nebulex.Time`. Modules with `@moduledoc false` are internal; that
includes every `Nebulex.Cache.*` feature module,
`Nebulex.Caching.Decorators.Runtime`, and `Nebulex.Telemetry`.

Tests: `test/nebulex/` mirrors `lib/nebulex/`; `test/shared/` holds the
`deftests` suites every adapter must pass; `test/support/` holds
`Nebulex.CacheCase`, `Nebulex.TestAdapter`, and the test caches. Adapter
repos fetch `test/shared/` and `test/support/` from a Nebulex checkout (they
are not in the Hex package).

The list of official adapters lives in `guides/introduction/nbx-adapters.md`;
do not maintain a parallel list in rule files.

---

## Design Decisions

Each of these is deliberate. Do not reverse one without a documented reason.

### ok/error tuples everywhere

Cache operations return `{:ok, value}` or `{:error, reason}`; bang variants
raise. Cache infrastructure failures are handled explicitly at each call
site, not swallowed. The exact conventions per operation are in
`nebulex.md` ("Return Value Conventions").

### Adapters are decoupled

The core has no runtime dependency on any adapter package; adapters depend
on core, never the reverse. The behaviours define the contract and
`use Nebulex.Cache` enforces it at compile time. A breaking change in an
adapter does not require a core release, and anyone can publish an adapter
without touching this repo.

### Minimal, mostly optional dependencies

The only required runtime dependency is `:nimble_options`. `:telemetry` and
`:decorator` are optional: when one is absent, the feature it enables is
unavailable, with no runtime error and no silent failure. Adding a required
dependency is an architectural change (Non-Negotiable #6).

### NimbleOptions for all option validation

Every public option set (cache, decorator, and adapter options) is a
NimbleOptions schema, so errors are consistent and raised at compile time or
startup. The schema also generates the docs.

### Telemetry is the observability contract

Every cache command emits a Telemetry span through
`Nebulex.Adapter.run_command/4`, whatever the adapter, so dashboards and
handlers keep working across backend switches. Adapters may emit extra
events but must not suppress or rename the core ones. The event shape is in
`nebulex.md` ("Telemetry").

### Nil is a valid cache value

Since v3, `nil` can be cached; it is not a cache-miss sentinel. Decorator
`:match` functions decide whether a result is cached.

---

## Non-Negotiables

These rules are not open for debate. A contribution that violates them is
not merged, whatever its other merits.

### 1. Adapters must remain decoupled from core

The core must not import, alias, or depend on any adapter module at
runtime. Shared utilities belong in `Nebulex.Adapters.Common.*` in core, not
in adapter packages. In an adapter repo the same rule reads: never edit
`deps/nebulex/`; propose the change in the core repo.

### 2. No breaking public API changes without a major version

`Nebulex.Cache`, `Nebulex.Caching`, and all `Nebulex.Adapter.*` callback
specs are public API. Removing or renaming public functions, changing
callback signatures, or altering option semantics requires a major version
(`v3.x` to `v4.0`). Deprecation warnings must precede removals by at least
one minor release.

### 3. Every public function must have a `@doc` and typespec

Every module has a `@moduledoc` (or `@moduledoc false`); every public
function has `@doc` and `@spec`. `mix doctor` enforces 100% `@moduledoc`
and at least 80% `@doc` coverage (`.doctor.exs`); `@spec` and the rest are
enforced in review.

### 4. New behaviour must have tests

Every new feature, option, or code path comes with tests. Adapter-facing
behaviour goes in `test/shared/` with `deftests`, so the shared suite covers
every adapter; behaviour adapters may legitimately not support is tested in
`test/nebulex/` against `Nebulex.TestAdapter`. Core-only changes are tested
in `test/nebulex/`.

### 5. The canonical gate must pass

Run the repo's gate alias before opening a PR; reviewers rely on green CI:

```bash
mix precommit
```

`mix.exs` `aliases/0` defines what it runs; in core that includes the docs
build with warnings as errors. Fix the root cause of a docs warning (a
reference to a hidden module, a broken link, a missing `@doc`); do not
suppress it.

### 6. Keep this document up to date

After any structural change (a new module, adapter callback, or required
dependency; a new option that changes the adapter contract; a change to the
layer boundaries), review the architecture doc of the repo you are in and
update it if needed. Do not copy here what the module docs already say.

---

## Source of Truth Hierarchy

When in doubt about intent, consult these in order:

1. `workflow.md`: contribution workflow and rule precedence.
2. This document: boundaries, design decisions, and non-negotiables.
3. `nebulex.md`: domain-specific patterns and pitfalls.
4. Module `@moduledoc` and function `@doc`: local intent for each API.
5. `CHANGELOG.md`: history of decisions and the reasoning behind them.
6. The blog post ["Nebulex v3: A New Chapter for Caching in Elixir"][v3-post]
   for the philosophy behind the v3 redesign.

[v3-post]: https://medium.com/erlang-battleground/nebulex-v3-a-new-chapter-for-caching-in-elixir-03cd366692c3
