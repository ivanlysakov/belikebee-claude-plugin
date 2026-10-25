# belikebee-claude-plugin

Claude Code marketplace with one plugin, `belikebee`, for the [BeLikeBee](https://github.com/ivanlysakov/belikebee.app) repo (Next.js modular monolith, see its `ARCHITECTURE.md`). The content assumes that repo's layout (`src/modules/<name>/`, `.claude/rules/<name>.md`, Vitest + Playwright), so it is not meant for other projects. More detail per component: [plugins/belikebee/README.md](plugins/belikebee/README.md).

## Purpose

BeLikeBee is one Next.js app split into modules (identity, apiary, billing, scheduling, notifications) that may only talk through each other's `index.ts` or domain events. Without the plugin, every feature needed the same long prompt (read the ADR and module rules, write a failing test first, prove the tests can fail, commit only your own files, append the `LOG.md` line), and Claude could still write deep cross-module imports that break the boundaries. The plugin packs that workflow into skills, blocks boundary-breaking imports before they are written and commits whose modules fail their tests, and drafts release notes from git history.

## Install

The BeLikeBee repo enables it in `.claude/settings.json` (`extraKnownMarketplaces` + `enabledPlugins`), so Claude Code offers to install it when the repo is opened. By hand, inside Claude Code:

```text
/plugin marketplace add ivanlysakov/belikebee-claude-plugin
/plugin install belikebee@belikebee-plugins
```

Check the manifests with `claude plugin validate .` and `claude plugin validate plugins/belikebee`.

## Commands

| Command | What it does | Example |
| --- | --- | --- |
| `/belikebee:release-notes [from-ref]` | Runs the repo's `scripts/release-notes.sh`: a `claude -p` call (schema-checked JSON, max 10 turns) drafts the `## [Unreleased]` section of `docs/CHANGELOG.md` from the commits since the last tag, then the script checks that every commit is covered. Leaves the diff for review; never commits. | `/belikebee:release-notes`, `/belikebee:release-notes v0.1.0` |
| `/belikebee:feature-plan` | Skill, see below. | `/belikebee:feature-plan booking slots in scheduling` |
| `/belikebee:feature-scaffold` | Skill, see below. | `/belikebee:feature-scaffold` (after the plan is agreed) |
| `/belikebee:feature-tests` | Skill, see below. | `/belikebee:feature-tests add E2E for hive photos` |
| `/belikebee:feature-ship` | Skill, see below. | `/belikebee:feature-ship` |

## Skills

Each skill also triggers on a plain request, so typing the command is optional. Together they form one cycle: plan → scaffold → tests → ship.

| Skill | Triggers | What it does |
| --- | --- | --- |
| `feature-plan` | "implement / add / build X in module Y", "how would we do X", "what would it take" | Sync check, reads the ADR, spec and module rules, runs the `pattern-scout` agent, asks the open decisions in one batch, writes a plan with an assumptions table and a verify check per step. Writes no code. |
| `feature-scaffold` | "implement / build / scaffold / create" once a plan exists or the scope is clear | Failing Vitest test first, then Zod schema, server action, Prisma models and migration, UI, thin routes in `src/app`; ends with typecheck, build and a deliberate-break check. |
| `feature-tests` | "add tests", "cover this with tests", "e2e", "integration tests" | Lists existing coverage, lets you pick levels (unit, DB integration on `belikebee_test`, Playwright E2E), writes them, proves each suite can fail. Never touches dev data. |
| `feature-ship` | "commit", "ship it", "wrap up", "prepare a PR" | Separates your changes from other sessions', reviews the diff, re-runs checks, stages explicit paths, scans for secrets, commits on `dev`, appends the `LOG.md` line. Pushing stays with you. |

Agent: `belikebee:pattern-scout` (Sonnet, read-only) finds the existing code and conventions a new feature should reuse and returns them with `file:line` references. `feature-plan` starts it first.

## Hooks

| Event | Matcher | Condition | Effect |
| --- | --- | --- | --- |
| `PreToolUse` | `Edit\|Write\|MultiEdit` | Target is a `.ts`, `.tsx`, `.js`, `.jsx` or `.mjs` file under `src/` (not `node_modules`); only the text being written is checked. | Exit 2 blocks the call and tells Claude which rule broke: a deep import into another module (`@/modules/billing/db/queries` or `../billing/...`), `src/shared` importing `src/modules` or `src/app`, a module importing `src/app`, or `identity` importing any other module. |
| `PreToolUse` | `Bash` | The command runs `git commit` (also `git -C <dir> commit` or after `cd`) and the working tree has changes under `src/modules/<name>/`, or in `src/shared`, `test/` or tooling config (then all modules). | Runs the Vitest unit tests of the changed modules, then their integration tests against `belikebee_test`. Exit 2 blocks the commit when a test fails or Postgres is down, with the failing test output. |

Needs `bash` (3.2+, the macOS default works) and `jq`; the commit hook also needs `pnpm` and Postgres (`docker compose up -d postgres`) when the changed modules have integration tests. Imports built from template strings are not caught; lint rules are the full solution once the repo has them.
