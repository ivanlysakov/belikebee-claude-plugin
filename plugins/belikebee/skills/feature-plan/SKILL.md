---
name: feature-plan
description: Plan a new BeLikeBee feature before any code is written — sync check, read the ADR/architecture/spec/module rules, surface conflicts and decisions that belong to the user, and produce a plan with an assumptions table and a verify check per step. Use this whenever the user asks to build, implement, add, or "create" something in src/modules/* or src/app (e.g. "implement registration in identity", "add booking slots", "let's do Monobank invoices"), asks "how would we do X" / "what would it take", or invokes /belikebee:feature-plan — even if they don't say "plan". Run it before /belikebee:feature-scaffold.
---

# Feature plan

The goal of this phase is that questions come **before** implementation, not after mistakes. You produce a plan the user can approve; you do not write application code here.

Why this matters in this repo: the stack, module boundaries, and many tool choices are already decided in docs, while some choices are explicitly *not* decided (e.g. there was no test runner until one was picked) and belong to the user. Guessing those silently is the most expensive mistake — it gets built on.

## 1. Check the ground truth

- `git fetch`, then `git status -sb` and `git log --oneline -3`. Report whether HEAD matches its upstream and which files are already dirty. Dirty files you didn't create belong to the user or another session sharing this checkout — note them now so `/belikebee:feature-ship` won't stage them later.
- If the user points at a handoff, plan, or earlier claim, check it against the real tree. Never carry a "done/green" claim forward without re-checking it.

## 2. Read the context that constrains the feature

Read only what applies, but don't skip the module-specific files — they hold the rules that are easiest to violate:

| File | What to take from it |
| --- | --- |
| `CLAUDE.md`, `ARCHITECTURE.md` | Module boundaries (only `index.ts` is public, `src/shared` never imports modules, events in `src/shared/events/`, each Prisma model owned by one module), workflow (commit on `dev`, no push), gotchas |
| `docs/adr/*.md` | Decided stack (Next.js App Router, Prisma, Zod, NextAuth v4, Tailwind + shadcn/ui, Monobank). Don't re-litigate these |
| `SPEC.md` | Roles, use cases, NFRs (security, privacy, localization) the feature must respect |
| `docs/bc-map.md` | Which domain events the context publishes/consumes |
| `src/modules/<name>/README.md` and `.claude/rules/<name>.md` | What the module owns and what is forbidden (e.g. identity may not import other modules; a new personal-data field must be justified and covered by export/deletion; a new role requires updating SPEC.md and bc-map.md in the same change) |
| Existing code in the module, `src/shared/`, `package.json`, `prisma.config.ts`, test configs | What already exists, so the plan reuses it instead of re-creating it |

For existing code, start the `belikebee:pattern-scout` subagent first with the feature in one or two sentences and the target module. It searches the codebase and returns what to reuse, which file to copy for each new piece, the boundaries and events, and what has no precedent yet, with `file:line` references. Read the rules above while it runs, and spot-check the claims the plan depends on. If the agent isn't available (it loads at session start), do the search yourself.

## 3. Check facts that change the plan

Verify instead of assuming; each of these bit a past session:

- **Package versions**: `npm view <pkg> version --cache $TMPDIR/npm-cache` (the sandbox can't write `~/.npm`). Check `npm view <pkg> dist-tags` too — `latest` can point at a release candidate (Prisma once tagged `8.0.0-rc` as latest); pin the newest stable instead.
- **Compatibility**: `npm view <pkg>@<major> peerDependencies` (e.g. next-auth v4 vs the current Next major).
- **Network hosts** the work will need (Prisma engines: `binaries.prisma.sh`; shadcn: `ui.shadcn.com`; Playwright browsers). Hosts must be in both allowlists (`.claude/settings.json` and `.devcontainer/init-firewall.sh`); Claude can't edit the settings file, so list missing hosts as a user step.
- **Runtime pieces**: is Postgres running (`docker compose ps postgres`, run outside the sandbox — inside it, localhost probes always fail and prove nothing)? Does the feature need new env vars? Claude can't read `.env`; plan user-run commands for it.

## 4. Find conflicts and real decisions

- **Request vs docs**: if the request contradicts the docs (e.g. "Role enum CLIENT, BEEKEEPER" while SPEC lists Admin too), present both readings and a recommendation. Don't pick silently.
- **User's call** (ask): stack defaults not fixed by the ADR (test runner, hashing library, where a schema file lives, where the DB runs), anything needing their credentials or machine (`.env` edits, Docker, pushes, allowlist edits), scope ambiguity, privacy-relevant fields.
- **Your call** (decide, state choice + alternative in one line): conventional defaults with low cost if wrong.

Ask all real questions in **one** `AskUserQuestion` batch, recommended option first with "(Recommended)" and a one-line trade-off per option. If a simpler approach exists, say so; push back when the request is more than the goal needs.

## 5. Write the plan

Use this structure (in chat unless the user asks for a file):

```markdown
## Goal
<one checkable sentence, e.g. "a signed-out user can register at /sign-up; a Vitest test reproduces the duplicate-email case and passes">

## Assumptions
| Assumption | How verified | Cost if wrong |
| --- | --- | --- |

## Decisions
- <decision> — chose X; alternative Y (one line each; mark which ones the user made)

## Steps
1. <step> — verify: <command and the output that proves it>
...

## Your steps
- <exact `! command` for anything Claude can't or shouldn't run, and what output to paste back>

## Out of scope
- <things deliberately not done, so nobody assumes they were>
```

Keep steps small enough that each has its own verify check. A good verify check could fail: "`pnpm test` shows the new test failing before the code exists" beats "tests pass".

## What not to do here

- Don't install packages, write code, or create migrations — that's `/belikebee:feature-scaffold`.
- Don't read or print `.env` contents in any form (even key names or lengths); the user has denied it before.
- Don't explain in jargon: write so a junior developer can follow, plain example before mechanics.
