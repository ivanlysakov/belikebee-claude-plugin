---
name: feature-scaffold
description: Implement an agreed BeLikeBee feature test-first inside its module — failing Vitest test first, then the minimum code in src/modules/<name>/ (Zod schema, server action, Prisma models + migration, UI pieces) and thin routes in src/app, finishing with typecheck, build, and a deliberate-break check that proves the tests catch regressions. Use this whenever the user says implement / build / scaffold / create / "add X to module Y" after a plan exists or the scope is already clear, or invokes /belikebee:feature-scaffold — even for "small" changes to a module. Also use it for "go", "go next", "next slice" while working through the slices of a /belikebee:feature-plan plan. If there is no plan and real decisions are open, run /belikebee:feature-plan first.
---

# Feature scaffold

You turn an agreed plan into working code with proof. "Done" means: a test that failed before the code existed now passes, the test demonstrably fails when the code is broken, and typecheck/build are green — all with command output from this session.

Before running commands, skim `references/environment.md` (next to this file). Most surprises in this repo are sandbox or tooling traps listed there, and recognizing them saves long detours.

## 0. Preconditions

- There is an agreed scope (a `/belikebee:feature-plan` result, or a request specific enough that no user decision is open). If the stack choice, a privacy-relevant field, or a module boundary is unclear, stop and ask — one `AskUserQuestion` batch.
- `git status -sb`: remember which dirty files are not yours.

## 1. Place the code where the architecture expects it

```text
src/modules/<name>/
├── <name>.prisma              # models this module owns (multi-file Prisma schema)
├── <feature>.schema.ts        # Zod schemas for external input
├── <feature>.action.ts        # "use server" actions; only async exports (+ types)
├── <feature>.ts               # plain server logic (e.g. authorize, queries)
├── ui/<component>.tsx         # "use client" pieces for this feature
├── <feature>.test.ts          # unit tests (Vitest)
└── index.ts                   # the ONLY file other code may import
src/app/<route>/page.tsx       # thin: renders module exports, no business logic
src/shared/events/index.ts     # event payload types when the module publishes
```

Rules worth re-checking as you write (they come from `ARCHITECTURE.md` and `.claude/rules/<name>.md`):

- Other modules and `src/app` import only `@/modules/<name>`; `src/shared` imports nothing from modules/app.
- `index.ts` exports only what other code needs **today**. When a new export replaces an old one, remove the orphan.
- Each table is read/written only by its owning module.
- Integrate across modules with domain events (`publish` from `@/shared/event-bus`), not direct calls.
- No speculative fields or features; personal-data fields must be justified by a use case.

## 2. Write the test first and watch it fail

1. Write `<feature>.test.ts` describing the behaviour from the plan's goal. Unit tests mock infrastructure at the module edge:

   ```ts
   const { createUser, publish } = vi.hoisted(() => ({ createUser: vi.fn(), publish: vi.fn() }));
   vi.mock("@/shared/db/client", () => ({ prisma: { user: { create: createUser } } }));
   vi.mock("@/shared/event-bus", () => ({ publish }));
   ```

   Cover the happy path, invalid input (nothing written), and the main failure the user will hit (e.g. duplicate email → field error, no event). Construct real Prisma errors when needed: `new Prisma.PrismaClientKnownRequestError("…", { code: "P2002", clientVersion: "7.10.1" })`.
2. Run `pnpm test` and show it failing for the right reason (missing module or wrong behaviour), not a typo.

## 3. Implement the minimum

Patterns that worked here:

- **Zod input**: normalize before validating, e.g. `z.string().trim().toLowerCase().pipe(z.email())`; restrict enums at the boundary (`z.enum([Role.CLIENT, Role.BEEKEEPER])` from `@/generated/prisma/enums`) even when the DB enum has more values.
- **Server actions for forms**: shape `(prevState, formData) => Promise<State>` for React's `useActionState`; `State` is a small union (`idle | success | error` with `fieldErrors` from `z.flattenError`). Map known Prisma errors (P2002 unique) to field errors; rethrow everything else.
- **Writes + events**: write in one Prisma call (nested `create` for owned children), then `publish` the domain event.
- **Secrets & passwords**: hash with `node:crypto` scrypt (existing `password.ts`); never return hashes from functions that leave the module.
- **UI**: shadcn components from `@/shared/ui`; client components in the module's `ui/`; pages stay thin.

Then run `pnpm test` until green.

## 4. Schema changes

If the feature adds or changes models:

1. Edit `src/modules/<name>/<name>.prisma`, then `pnpm exec prisma validate` and `pnpm db:generate`.
2. Create the migration (see `references/environment.md` → Migrations), read the SQL, and check it does only what the model change implies.
3. Applying it to the dev DB changes shared state: give the user `! pnpm exec prisma migrate deploy`, or run it outside the sandbox if they've asked you to; confirm with `prisma migrate status`.

## 5. Prove the tests can catch a regression

A test that has never failed proves nothing. For each new behaviour that matters:

```bash
f=src/modules/<name>/<file>.ts; cp $f $TMPDIR/<file>.bak
sed -i '' 's/<guarded line>/<broken version>/' $f; grep -c '<broken version>' $f   # confirm the edit applied
pnpm test 2>&1 | grep -E "×|Tests "                                                     # expect the named test to fail
cp $TMPDIR/<file>.bak $f; pnpm test 2>&1 | grep "Tests "                                # restored and green
```

Pick mutations the test is *designed* to catch (e.g. allow ADMIN at sign-up, store the plain password, skip the password check). If a mutation doesn't fail any test, either the test is weak or the mutation was not meaningful — decide which and say so.

## 6. Verify

- `pnpm test` (unit), `pnpm typecheck`, and `pnpm build` when routes/UI changed. `next build`/`next dev` load `.env`, so run them outside the sandbox.
- **Dev smoke check**, required when routes, pages, server components, messages or i18n changed: start `pnpm dev` in the background (outside the sandbox), curl every new or changed route signed out (a protected route should redirect, not answer 500), and read the dev server output for `⨯` or `Error`. A 500 or an error in that output means not done, even with green tests and build: `next dev` compiles routes in a different order than `next build` (see `references/environment.md`). Stop the server afterwards.
- For UI flows, offer the user a short manual test script, or `/belikebee:feature-tests` for E2E.
- `grep` the new files' imports to confirm no boundary violations.

## 7. Report

Lead with the outcome, then:

- what was built (table: file → what it does),
- checks run this session with their result (and anything **unverified**),
- the assumptions table (assumption | how verified | cost if wrong),
- user steps as exact `! commands` with the output to paste back,
- what's left (e.g. "not committed — run /belikebee:feature-ship").

Don't commit here; shipping is a separate step the user triggers.
