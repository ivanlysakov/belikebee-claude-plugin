# belikebee

Claude Code plugin for building features in the BeLikeBee repo, a Next.js modular monolith where each bounded context lives in `src/modules/<name>/` and modules talk only through their public `index.ts` or domain events. The plugin turns that repo's feature workflow into four skills, adds a release-notes command, a subagent that finds existing code to reuse, and adds a hook that stops Claude from writing imports that break the module boundaries.

It is written for that repo's layout and tooling (`ARCHITECTURE.md`, `.claude/rules/<name>.md`, Prisma multi-file schema, Vitest, Playwright, Postgres in `docker compose`), so it is not meant for other projects.

## Install

The BeLikeBee repo enables it in `.claude/settings.json`, so Claude Code offers to install it when the repo is opened. By hand:

```text
/plugin marketplace add ivanlysakov/belikebee-claude-plugin
/plugin install belikebee@belikebee-plugins
```

## Workflow

A feature goes through four steps, one skill each. Every skill also triggers on plain requests ("implement booking slots", "add tests", "commit"), so typing the command is optional.

| Step | Command | What it does |
| --- | --- | --- |
| 1. Plan | `/belikebee:feature-plan` | Checks the git state, reads the ADR, spec and module rules, runs `pattern-scout`, asks the open decisions in one batch, and writes a plan with an assumptions table and a verify check per step. Writes no code. |
| 2. Build | `/belikebee:feature-scaffold` | Implements the agreed plan test-first inside the module: failing Vitest test, then the Zod schema, server action, Prisma models and migration, UI, and thin routes in `src/app`. Ends with typecheck, build and a deliberate-break check that proves the tests catch regressions. |
| 3. Test | `/belikebee:feature-tests` | Lists what is already covered, lets you pick the missing levels (unit, DB integration on `belikebee_test`, Playwright E2E), writes them on the existing test setup, and proves each suite can fail. Never touches dev data. |
| 4. Ship | `/belikebee:feature-ship` | Separates your changes from other sessions' files, reviews the diff, re-runs the checks, stages explicit paths, scans for secrets, commits on `dev`, and appends the `LOG.md` line. Pushing stays with you. |

## Command: `/belikebee:release-notes [from-ref]`

Runs the repo's `scripts/release-notes.sh`, which calls `claude -p` with `--json-schema`, `--max-turns 10` and only `git log`, `Read(docs/*)` and `Edit(docs/**)` allowed. Claude rewrites the `## [Unreleased]` section of `docs/CHANGELOG.md` from the commits since the last tag (or `from-ref`), and the script checks that every commit is covered by both the notes and the changelog. The result stays in the working tree for review; the command never commits.

## Subagent: `belikebee:pattern-scout`

A read-only search, run at the start of planning. Give it the feature in a sentence or two and the target module, and it returns a short report with `file:line` references: what to reuse as is, which existing file to copy for each new piece (schema, action, model, form, route, each test level), the module boundaries and events involved, what has no precedent yet, and where the code is inconsistent. It runs on Sonnet and uses Bash only for read-only commands.

## Hook: module boundaries

Runs before every Edit, Write and MultiEdit on `.ts`, `.tsx`, `.js`, `.jsx` and `.mjs` files under `src/`. It checks only the text being written, so existing code never blocks an unrelated edit. It blocks:

- deep imports into another module (`@/modules/billing/db/queries`; use `@/modules/billing`), including relative paths such as `../billing/...`;
- `src/shared` importing from `src/modules` or `src/app`;
- a module importing from `src/app`;
- `identity` importing any other module (its rules allow none).

A blocked call returns the rule it broke, so Claude can fix the import. The check matches import text with a regular expression, so imports built from template strings are not caught; lint rules are the complete solution once the repo has them.

## Requirements

- `bash` (3.2 or newer, so the macOS default works) and `jq` for the hook.
- The BeLikeBee repo with Postgres running (`docker compose up -d postgres`) for integration and E2E tests.
