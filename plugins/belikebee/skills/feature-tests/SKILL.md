---
name: feature-tests
description: Add the missing test levels for a BeLikeBee feature — inventory what is already covered, let the user pick levels (unit, DB integration against belikebee_test, Playwright E2E on a production build), write the tests on the existing test infrastructure, and prove each suite with a deliberate-break check without ever touching dev data. Use this whenever the user says "add tests", "cover this with tests", "test the flow", "e2e", "integration tests", "make sure X is tested", or invokes /belikebee:feature-tests, including right after a feature was scaffolded or manually verified.
---

# Feature tests

You add tests that would catch real regressions in a feature, at the levels the user wants, and you prove each suite can fail. Mocked unit tests already exist for most features; the gaps are usually wiring (e.g. session callbacks), the real database, and the full user flow.

Skim `../feature-scaffold/references/environment.md` (relative to this skill's base directory) first: DB and browser tests here run into sandbox limits (localhost is blocked, `.env` unreadable), and knowing that up front avoids misdiagnosing failures.

## 1. Inventory before proposing

```bash
grep -rnE "^\s*(describe|it|test)\(" src e2e --include=*.ts
```

List what each existing test proves and what nothing proves yet. Typical gaps:

| Gap | Level that covers it |
| --- | --- |
| Behaviour of pure logic, validation, error mapping | Unit (Vitest, mocks at `@/shared/db/client` / `@/shared/event-bus`) |
| Real constraints: unique indexes, cascades, nested writes, real Prisma error codes | Integration (`*.int.test.ts`, real `belikebee_test`) |
| Wiring across framework pieces (NextAuth callbacks, server actions + forms, redirects) | E2E (Playwright) — or a focused unit test of the callback |
| What the user does by hand in the browser | E2E |

## 2. Let the user choose levels

Ask once (`AskUserQuestion`, `multiSelect: true`) with each option's cost: new dependencies, downloads (Playwright Chromium ≈150 MB, Playwright CDN must be allowlisted), Docker/Postgres requirement, run time, overlap with other levels. Recommend the level that matches what the user just verified manually (usually E2E). Mention which gaps stay uncovered by their choice.

## 3. Use (and extend) the existing infrastructure

Already in the repo — reuse it rather than creating parallel setups:

- `test/test-database.ts`: `TEST_DATABASE_URL` (`belikebee_test` on the dev Postgres) and `resetTestDatabase()` = `prisma migrate deploy` + `TRUNCATE`. When a feature adds tables not reached by `TRUNCATE "User" CASCADE`, extend the TRUNCATE list.
- `vitest.config.ts` projects: `unit` (`src/**/*.test.ts`, excluding `*.int.test.ts`) and `integration` (`src/**/*.int.test.ts`, globalSetup resets the test DB, `DATABASE_URL` overridden, files run serially).
- `playwright.config.ts`: builds and serves the app on port 3100 with `DATABASE_URL` = test DB and `NEXTAUTH_URL` = `http://localhost:3100`; `e2e/global-setup.ts` resets the test DB. Runs next to `pnpm dev` on 3000.
- Scripts: `pnpm test` (unit only, no Docker needed), `pnpm test:int`, `pnpm test:e2e`.

If some of this is missing (e.g. a new repo state), build the same shape: separate `_test` database, reset per run, env override, separate port.

## 4. Protect dev data before anything destructive

Resetting "the test DB" while the connection actually points at dev wipes the user's data. Before the first run that truncates or migrates:

- Confirm the override wins: a shell `DATABASE_URL` beats `.env` for `process.loadEnvFile()` and for Next.js (re-verify with a throwaway `.env` in `$TMPDIR` if the loading code changed).
- After the runs, count test rows in the **dev** DB (outside the sandbox) and expect 0, e.g. `select count(*) from "User" where email like '%@example.test'`.

## 5. Write the tests

- **Integration**: no mocks. Exercise the real action/query and then read the DB to assert rows, relations and constraint behaviour (e.g. duplicate email in different case → field error and still one row). Subscribe to the real event bus to assert published events. `afterAll(() => prisma.$disconnect())`.
- **E2E**: unique data per test (`user-${Date.now()}-${n}@example.test`), helpers for repeated flows (`signUp`, `signIn`), role/label locators (`getByRole("button", { name: "Create account" })`, `getByLabel("Email")`). Watch for strict-mode clashes when two elements share a name (e.g. a "Sign in" link in the page footer and on the success message) — navigate directly instead. Assert the outcome the user sees ("Signed in as … (BEEKEEPER)"), and the signed-out state after sign-out.
- Add new folders to `tsconfig.json` `include` and Playwright output (`/test-results`, `/playwright-report`) to `.gitignore` if not there.

## 6. Prove each suite

Run the deliberate-break check per suite, targeting code that **only this suite** covers (e.g. remove the line that copies `role` into the session → only E2E can catch it; drop the nested Profile create → integration catches it). Back up to `$TMPDIR`, apply with `sed`, confirm the edit applied, run the suite, expect the named test to fail, restore, expect green.

If a break doesn't fail the suite, think about why before moving on: a catch-all mutation (e.g. "treat every error as duplicate") can't fail a duplicate-email test because the observable result is identical. Choose a mutation that changes what the test observes (e.g. expect error code P2003 instead of P2002 — proves the real DB returns P2002).

## 7. Run everything and report

DB and E2E suites need Postgres up (`docker compose up -d postgres`) and run outside the sandbox. Run `pnpm test`, `pnpm test:int`, `pnpm test:e2e`, `pnpm typecheck` and report a table:

| Command | What it covers | Result |
| --- | --- | --- |

Then: what each new test proves, the deliberate-break results (including any that didn't discriminate and why), the dev-DB check, new files, and what remains untested. Don't commit — that's `/belikebee:feature-ship`.
