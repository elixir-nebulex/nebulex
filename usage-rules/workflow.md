# Agent Workflow

## Rule Index

Start here, then read these at session start and refer back while coding:

- `usage-rules/nebulex.md` - Nebulex-specific rules
- `usage-rules/elixir-style.md` - Style guidelines
- `usage-rules/elixir.md` - Core Elixir rules

> If these files are not found, check `AGENTS.md` or the local
> `usage-rules/` folder instead.

## Rule Precedence

When rules conflict, prioritize them in this order:

1. `usage-rules/workflow.md`
2. `usage-rules/nebulex.md`
3. `usage-rules/elixir-style.md`
4. `usage-rules/elixir.md`

> If these files are not found, apply the same precedence to the
> corresponding sections in `AGENTS.md`.

## Session Bootstrap

At the start of each session, quickly establish context:

1. Run `git status --short` and `git diff --name-only` to check
   local modifications and currently touched files.
2. Run `git log --oneline -20` to see recent changes.
3. Run `git branch -a` to see active branches and current branch.
4. Read `README.md` and the latest section of `CHANGELOG.md`.
5. Check `.tool-versions` or the `elixir` version in `mix.exs` for
   supported Elixir/OTP versions.

If on a feature branch, also run:

6. `git log --oneline main..HEAD` to see the branch's commits.
7. `git diff main...HEAD` to understand the branch's full scope.

When relevant to the task:

8. Check open issues and PRs with `gh issue list` and `gh pr list`.
   If `gh` is unavailable or unauthenticated, skip this step.

## Current Project Status

- **Latest release**: check the latest section in `CHANGELOG.md`.
- Read `CHANGELOG.md` for recent features, breaking changes, and
  the project's direction.
- Changelog policy: user-visible behavior changes should be documented;
  internal refactors may be omitted before a release.

## PR Workflow

### Reviewing PRs

1. Read the PR description and all comments:
   `gh pr view <number>` and `gh pr view <number> --comments`.
2. Review the diff: `gh pr diff <number>`.
3. Check `CHANGELOG.md` to understand if the change aligns with the
   project's direction.
4. Verify code follows `usage-rules/` conventions (Elixir patterns,
   Nebulex-specific rules, style guidelines).
5. Run the validation commands (see below) before approving.
6. Provide constructive feedback referencing specific lines and
   conventions.
7. Structure review feedback as:
   - findings first (ordered by severity, with file:line references),
   - open questions/assumptions,
   - brief summary last.

### Opening PRs

1. Branch from `main` with a descriptive branch name
   (e.g., `fix/some-bug`, `feat/cache-warming-support`).
2. Update `CHANGELOG.md` under the appropriate section
   (Enhancements, Bug fixes, Backward-incompatible changes).
3. Run all validation commands before pushing.
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
3. Use a scope when it adds clarity (e.g., `cache`, `decorators`,
   `telemetry`, `workflow`).
4. Keep the first line concise (ideally <= 72 chars).

### Examples

- `feat(cache): add runtime option validation for ttl`
- `fix(decorators): handle nested context pop safely`
- `chore(workflow): refine session bootstrap steps`

## Validation Commands

Before submitting or approving any code change, run:

```bash
# Quick targeted validation (recommended first)
mix test path/to/changed_test.exs

# Format check
mix format --check-formatted

# Static analysis
mix credo --strict

# Documentation (if docs were changed)
mix docs
```

Then run full-suite validation before merge/release:

```bash
mix test.ci
```
