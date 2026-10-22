---
name: feature-ship
description: Ship finished BeLikeBee work as a clean commit on dev — separate your changes from the user's and other sessions', review that every changed line belongs to the feature, re-run checks for fresh evidence, stage explicit paths only, scan the staged diff for secrets, commit with a descriptive message, append the required LOG.md line, and hand the push to the user. Use this whenever the user says "commit", "ship it", "wrap up", "let's commit this", "prepare a PR", or invokes /belikebee:feature-ship.
---

# Feature ship

You turn a working tree into one reviewable commit that contains exactly the feature — nothing the user didn't ask for, nothing from another session, no secrets — plus the project's LOG.md record. Pushing stays with the user (`git push` is denied for Claude).

## 1. Sort the working tree

```bash
git fetch && git status -sb && git status --short && git diff --stat
```

Classify every changed or untracked path:

- **Yours, for this feature** → will be staged.
- **The user's or another session's** (often `CLAUDE.md`, `.claude/settings.json`, `.devcontainer/init-firewall.sh`, personal notes like `manual_log.md`) → never stage. This checkout can be shared by several sessions.
- **Generated or undecided** (e.g. `AGENTS.md` written by `next dev`, build output) → don't stage; ask the user.

For a tracked file that has both your edits and someone else's, look at `git diff <file>`; if the hunks are mixed, ask before staging it.

Branch check: commits go on `dev`. If you're on `main`, stop and ask. (In a temporary worktree, its current branch stands in for `dev`.)

## 2. Review the diff like a reviewer

Read `git diff` (tracked files) and the new files. Every changed line should trace to the feature. Remove debug output and orphans your own change created; mention unrelated dead code rather than deleting it.

## 3. Fresh evidence

Claims in the commit and report need output from this session. Re-run what applies: `pnpm test`, `pnpm test:int` / `pnpm test:e2e` if those suites exist and the feature touches them (outside the sandbox, Postgres up), `pnpm typecheck`, `pnpm build` for route/UI changes. If something can't run, say "unverified" rather than carrying an old result forward.

## 4. Stage explicit paths and look at what's staged

```bash
git add <path> <path> …        # never `git add -A` or `git add .`
git status --short             # confirm: staged = yours, unstaged/untracked = everything else
```

Lockfiles come along when dependencies changed (`pnpm-lock.yaml` with `package.json`).

## 5. Scan the staged diff for secrets

```bash
git diff --cached -- . ':!pnpm-lock.yaml' | grep -inE '^\+.*(secret|token|api[_-]?key|password\s*[:=]|BEGIN [A-Z ]*PRIVATE KEY)'
```

Read each hit. Code identifiers (`token.role`, `passwordHash`) are fine; real values are not. Dev-only values that are intentionally committed (the local Postgres login `postgres`/`postgres`) should be named in your report. Never stage `.env*` (except an `.env.example` the user changed themselves) and never print `.env` contents.

## 6. Commit

Message: `<module or area>: <what changed, imperative, ≤72 chars>`, blank line, then short bullets of what a reviewer needs (models/migrations, public API, routes, tests and their counts). Pass it via `git commit -F -` with a heredoc. Add attribution lines only if the session's instructions provide them.

```bash
git commit -q -F - <<'EOF'
identity: user registration, sign-in pages and tests

- Prisma models User and Profile with Role enum; initial migration
- registerUserAction (Zod + scrypt), publishes UserRegistered
- Tests: unit (10), integration (3), Playwright E2E (3)
EOF
git log --oneline -1 && git status --short
```

## 7. LOG.md (when the commit touches `src/modules/`)

The project requires one line appended to `LOG.md` in the repo root after each such commit (create the file if missing):

```text
<timestamp> | <short description (hash)> | repeated prompts: "<verbatim>" | manual checks: <tests, migration check, lint> | stumbles: <errors, rollbacks, rework> | time: <first prompt → green test>
```

- Timestamp: `date +%Y-%m-%dT%H:%M:%S%z`.
- `repeated prompts`: prompts the user had to repeat verbatim this session; `none` if none.
- `manual checks`: the checks actually run (with counts), including what the user verified by hand.
- `stumbles`: errors, rollbacks and rework, briefly — this is the honest part; don't polish it.
- `time`: first prompt → first green test, from real timestamps (logs, test start times); mark estimates with `≈`.
- Use `none` for an empty field.

`LOG.md` is written after the commit, so it stays uncommitted; tell the user and offer to include it in the next commit (or commit it alone if they prefer).

## 8. Hand over

Report: commit hash and subject, number of files, what was deliberately left out and why, the secret-scan result, the LOG.md line status, and the user's next steps — `! git push`, then a PR `dev` → `main` when ready. Mention anything still open (undecided files, background dev server still running).
