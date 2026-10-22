# Environment traps (BeLikeBee on the macOS host)

Claude runs every Bash command inside a macOS sandbox. Many failures here are the sandbox, not the code. Read the error before "fixing" anything: `Operation not permitted`, `EPERM`, or a `<sandbox_violations>` block means sandbox.

## Sandbox boundaries

| Symptom | Cause | What to do |
| --- | --- | --- |
| `npm view` / `pnpm dlx` fail with EPERM on `~/.npm` or `~/Library/Caches/pnpm` | Caches live outside the writable area | `npm view <pkg> --cache $TMPDIR/npm-cache`, `pnpm --config.cache-dir=$TMPDIR/pnpm-cache dlx …` |
| Request to a host blocked (403 / sandbox_violations) | Host not in allowlist | Re-run that one command with `allowed_domains: ["<host>"]`; tell the user to add the host to **both** `.claude/settings.json` and `.devcontainer/init-firewall.sh` (Claude can't edit settings.json) |
| `pg_isready` "no response", `nc` "closed", curl to `localhost:3000` fails | Sandbox blocks localhost TCP | Re-run outside the sandbox (`dangerouslyDisableSandbox: true`). A localhost probe inside the sandbox proves nothing |
| `.env: operation not permitted`, `docker compose` fails on stat `.env` | `.env*` is read-denied | Run tools that load `.env` (next dev/build/start, docker compose, prisma CLI against a DB) outside the sandbox. Never read `.env` yourself — not even key names; the user has denied it |
| File in `node_modules` "does not exist" though `ls` shows it | A sandbox deny pattern matches the filename (e.g. `credentials*` once hid `next-auth/providers/credentials.d.ts`) | `ls -la` the real path; if EPERM, run that command outside the sandbox and tell the user they can adjust it with `/sandbox` |

Commands that need the user (give the exact `! command` and what output to paste back):

- Editing `.env` / `.env.example`. Use forms that print nothing, and make sure the file ends with a newline first, e.g. `! grep -q '^KEY=' .env || echo 'KEY=value' >> .env`. Secrets: `echo "NEXTAUTH_SECRET=$(openssl rand -base64 32)" >> .env`.
- `git push`, anything with their credentials, allowlist edits.

## Tooling facts

- **pnpm store**: `.npmrc` pins `store-dir=.pnpm-store` (repo-local, gitignored) so sandboxed and unsandboxed installs agree. Without it, pnpm aborts with `ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY`. Don't remove it.
- **Prisma 7**: multi-file schema — `prisma.config.ts` has `schema: "src"`; models live in `src/modules/<name>/<name>.prisma`, datasource/generator in `src/shared/db/schema.prisma`, migrations in `src/shared/db/migrations`. Prisma 7 does not read `.env` itself; `prisma.config.ts` calls `process.loadEnvFile()` (an existing shell variable wins over `.env` — verified). Generated client is `src/generated/prisma` (gitignored): run `pnpm db:generate` in a fresh worktree. The CLI downloads its engine from `binaries.prisma.sh`. Prisma refuses destructive commands (`migrate reset` etc.) from AI agents without user consent — never set `PRISMA_USER_CONSENT_FOR_DANGEROUS_AI_ACTION` yourself; ask the user.
- **Migrations**: first migration was generated offline with `prisma migrate diff --from-empty --to-schema src --script`. With the DB running, prefer `pnpm exec prisma migrate dev --create-only --name <name>` (outside the sandbox), review the SQL, then apply with `pnpm exec prisma migrate deploy` and confirm with `prisma migrate status` → "Database schema is up to date!".
- **Dev Postgres**: `docker compose up -d postgres` (service in `.devcontainer/docker-compose.yaml`, `postgres:17`, `127.0.0.1:5432`, dev-only login postgres/postgres, DB `belikebee`). Tests use `belikebee_test` on the same container.
- **Next.js 16 + NextAuth v4**: next-auth's `signIn(..., { redirect: false })` returns `ok: true` even for bad credentials — check `result.error`. Next rewrites `tsconfig.json` on first build (expected). `next dev` may generate `AGENTS.md` in the root — ask the user whether to keep it.
- **Dev server**: start with `pnpm dev` as a background command outside the sandbox; restart it after any `.env` change. Check readiness with curl (outside the sandbox) rather than sleeping.
- **shadcn CLI**: use `add <component>` against the existing `components.json` (UI kit goes to `src/shared/ui`). The 4.x CLI has skipped dependencies (`class-variance-authority`) and theme variables before — after adding, check every import resolves and the tokens used (`bg-primary`, …) exist in `src/app/globals.css`. The `cn` package is shadcn's official helper.
- **Browser automation**: a password-manager extension can overlay the page and block screenshots/clicks ("Cannot access a chrome-extension:// URL of different extension"). Stop after 2–3 failures and ask the user; don't loop.
