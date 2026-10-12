# Agent Workflow

## Rules

When rules conflict, prioritize them in the order listed.

1. `workflow.md` — entry point (this file)
2. `architecture.md` — core architecture & non-negotiables
3. `nebulex.md` — Nebulex-specific rules
4. `elixir-style.md` — style guidelines
5. `elixir.md` — core Elixir rules

Human contributors have `CONTRIBUTING.md`; these files are the agent-facing
source of the same conventions.

## Non-Negotiable Style Rules

These are the rules reviewers reject most often. The full guides are
`elixir-style.md` and `nebulex.md`; these apply even when you have not read
them.

1. In a multi-clause function, never follow a `do ... end` clause with a
   `, do:` one-liner. Single-line clauses may only come first; if one
   clause is multiline, make the later ones multiline too.
2. Put a blank line before the final expression of a multiline function
   body, and write a pipeline that is the return value on multiple lines.
3. Do not pipe a single call (`foo |> bar()`); call it directly.
4. Code wraps at 100 columns; prose in docs and comments wraps at 80.
5. Comments start with a capital letter and use punctuation; `##` marks a
   section, `#` a comment.
6. `@spec` goes directly under `@doc`; types are written with parentheses
   (`@type t() :: ...`).
7. In tests, the expression under test goes on the left, the expected value
   on the right, and `==` is used when the expected value is fully known.
8. Return `{:ok, value}` / `{:error, reason}`; never a bare `:error`.

## Scope: Core vs Adapter Repos

These rules are shared. They live in `usage-rules/` in the Nebulex core
repository and ship in the `nebulex` Hex package, so adapter repositories
(`nebulex_local`, `nebulex_distributed`, `nebulex_redis_adapter`, etc.)
consume them from `deps/nebulex/usage-rules/`.

- You are in the core repo when `mix.exs` has `app: :nebulex`. Everything
  here applies as written.
- Otherwise you are in an adapter repo. The repo's own `AGENTS.md` and its
  own architecture doc (if any) take precedence over anything here that
  names a core-only path, command, or module. Sections marked
  "(core repo only)" describe the core package; read them for context, not
  as instructions.
- Never edit files under `deps/`; the shared rules are changed in the core
  repo.

## Session Bootstrap

At the start of each session:

1. Run `git status --short` and `git log --oneline -20` to see local
   modifications and recent changes. Leave unrelated local changes
   untouched and do not stage them; mention them in your final report.
2. Read the "Non-Negotiables" section of `architecture.md`.
3. Read `nebulex.md`.

Read the rest of `architecture.md`, `elixir-style.md`, and `elixir.md` when
the task touches their area (structural changes, style questions, general
Elixir patterns).

If on a feature branch, also run:

4. `git log --oneline main..HEAD` to see the branch's commits.
5. `git diff main...HEAD` to understand the branch's full scope.

When relevant to the task:

6. Read the `Unreleased` section of `CHANGELOG.md` for recent features,
   breaking changes, and the project's direction.
7. Check open issues and PRs with `gh issue list` and `gh pr list`.
   If `gh` is unavailable, unauthenticated, or lacks token scopes, skip
   this step and say so.

### Supported Versions

The CI matrix in `.github/workflows/ci.yml` is the source of truth for the
supported Elixir/OTP versions. `.tool-versions` is the local development
version, and the `elixir` requirement in `mix.exs` is only a lower bound. Do
not use language features newer than the oldest version in the CI matrix.

## PR Workflow

### Reviewing PRs

1. Read the PR description and all comments:
   `gh pr view <number>` and `gh pr view <number> --comments`. If `gh`
   fails (unavailable, unauthenticated, or insufficient token scope), fall
   back to `git show <sha>` and `git log --grep "#<number>"`, and note in
   the review which inputs were unavailable.
2. Review the diff: `gh pr diff <number>`.
3. Check the `Unreleased` section of `CHANGELOG.md` to understand if the
   change aligns with the project's direction.
4. Verify code follows the rules, in the precedence order listed in the
   Rules section above.
5. Rely on green CI for the canonical gate (`gh pr checks <number>`);
   re-run the gate locally only if you doubt CI's result. Use the
   fast-iteration commands (see below) for spot checks.
6. Provide constructive feedback referencing specific lines and
   conventions.
7. Structure review feedback as:
   - findings first, each labelled High (blocks merge), Medium (fix before
     merge), or Low (nit), with file:line references,
   - open questions/assumptions,
   - brief summary last, ending with a verdict: approve, approve with
     nits, or request changes.

### Opening PRs

1. Branch from `main` with a descriptive branch name
   (e.g., `fix/some-bug`, `feat/cache-warming-support`).
2. Never edit `CHANGELOG.md`. Only maintainers update it, when merging or
   releasing. Put release-note context in the PR description instead, and
   distinguish user-visible behavior from internal refactors; only the
   former warrants release-note context.
3. Run the canonical gate before pushing (see below).
4. Reference related GitHub issues in the PR description
   (e.g., "Closes #123").
5. Use `gh pr create` with a clear title and description.

## Commit Messages

Commit messages must follow the
[Conventional Commits](https://www.conventionalcommits.org/) format:

```text
type(scope): short summary
```

### Allowed Types

- `feat`
- `fix`
- `refactor`
- `docs`
- `test`
- `chore`
- `perf`
- `ci`
- `build`

### Rules

1. Use imperative mood in the summary.
2. Keep the summary lowercase and do not end it with a period.
3. Use a scope when it adds clarity. The scope is the layer or feature
   touched, not the file. In core: `cache` for `lib/nebulex/cache*`,
   `adapter` for `lib/nebulex/adapter*` and `lib/nebulex/adapters/`,
   `kv`/`queryable`/`transaction`/`observable`/`info` for a change
   confined to that feature, `decorators`, `telemetry`, `deps`, `docs`,
   `workflow`. In adapter repos use the adapter name (`local`,
   `partitioned`, ...) or the module area.
4. Keep the first line concise (ideally <= 72 chars).
5. For routine changes, the subject line alone is enough; add a body only
   when the "why" is not obvious from the diff.

### Examples

- `feat(cache): add runtime option validation for ttl`
- `fix(decorators): handle nested context pop safely`
- `chore(workflow): refine session bootstrap steps`

## Validation Commands

Use these for fast iteration during development:

```bash
# Targeted test
mix test path/to/changed_test.exs

# Format check
mix format --check-formatted

# Static analysis
mix credo --strict

# Documentation (if docs were changed)
mix docs
```

Files under `test/shared/` are `deftests` modules, not test files: running
`mix test test/shared/...` executes nothing. Run the test module that
includes them (in core, `test/nebulex/cache_test.exs` via
`use Nebulex.CacheTestCase`; in adapter repos, the adapter's test module).

### Canonical Gate

Before pushing for review, run the repo's gate alias. `mix.exs` `aliases/0`
is the source of truth for what it runs.

```bash
mix precommit
```

In the core repo the alias runs, in order: `deps.unlock --check-unused`,
`deps.audit`, `compile --warnings-as-errors`, `format --check-formatted`,
`credo --strict`, `coveralls.html`, `sobelow --skip --exit Low`,
`dialyzer --format short`, and `doctor`. CI runs the same checks
individually (with `coveralls.json` and `dialyzer --format github`); lint,
Sobelow, Dialyzer, and doctor run only on the newest matrix entry. Adapter
repos define their own alias (some still name it `test.ci`) with a subset
of these steps.

Green CI is a requirement, not a courtesy check (see `architecture.md`
Non-Negotiable #5).
