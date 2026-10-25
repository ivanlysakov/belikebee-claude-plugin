#!/usr/bin/env bash
# PreToolUse hook (Bash): before Claude runs `git commit`, runs the unit and integration tests of every
# module with changes. Changes in src/shared, test/ or tooling config run all tests.
# Exit 2 blocks the commit and shows stderr to Claude; exit 0 lets it through.
# Needs jq. Written for bash 3.2 (macOS /bin/bash) and BSD or GNU tools.

input=$(cat)
command=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")

commit_re='(^|[^[:alnum:]_-])git(([[:space:]]+-C[[:space:]]+[^[:space:]]+)*)[[:space:]]+commit([^[:alnum:]_-]|$)'
[[ "$command" =~ $commit_re ]] || exit 0
match=${BASH_REMATCH[0]} git_c=${BASH_REMATCH[2]}

# Where the commit runs: `git -C <dir> commit`, else the last `cd <dir>` before it, else the session cwd.
before=${command%%"$match"*}
dir=$(grep -oE '(^|&&|;)[[:space:]]*cd[[:space:]]+[^[:space:];&]+' <<<"$before" | tail -1 | sed -E 's/.*cd[[:space:]]+//')
[ -n "$git_c" ] && dir=$(sed -E 's/.*-C[[:space:]]+//' <<<"$git_c")
dir=$(sed -E "s/^[\"']|[\"']\$//g" <<<"${dir:-.}")
root=$(cd "${cwd:-.}" 2>/dev/null && git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0

# Staged, unstaged and untracked changes: covers `git add … && git commit` in one command.
changed=$({ git -C "$root" diff --name-only HEAD; git -C "$root" ls-files --others --exclude-standard src; } | sort -u)

run_all=0
grep -qE '^(src/shared/|test/|vitest\.config\.ts$|package\.json$|pnpm-lock\.yaml$|tsconfig\.json$|prisma\.config\.ts$)' <<<"$changed" && run_all=1
modules=$(sed -nE 's#^src/modules/([^/]+)/.*#\1#p' <<<"$changed" | sort -u)
[ $run_all = 1 ] || [ -n "$modules" ] || exit 0

filters=()
if [ $run_all = 1 ]; then
  scope="all modules (shared code or tooling changed)"
else
  scope=$(paste -sd, - <<<"$modules" | sed 's/,/, /g')
  for name in $modules; do filters+=("src/modules/$name/"); done
fi

block() {
  printf 'Commit blocked: %s (scope: %s).\n\n%s\n\nFix the failure, then commit again.\n' \
    "$1" "$scope" "$(sed $'s/\033\\[[0-9;]*m//g' <<<"$2" | tail -40)" >&2
  exit 2
}

vitest() {
  (cd "$root" && FORCE_COLOR=0 pnpm exec vitest run --project "$1" --passWithNoTests ${filters[@]+"${filters[@]}"} 2>&1)
}

output=$(vitest unit) || block "unit tests failed" "$output"

# Integration tests need the dev Postgres container (they use the belikebee_test database on it).
integration_tests=$(git -C "$root" ls-files --cached --others --exclude-standard -- 'src/**/*.int.test.ts')
[ $run_all = 1 ] || integration_tests=$(grep -E "^src/modules/($(paste -sd'|' - <<<"$modules"))/" <<<"$integration_tests")
if [ -n "$integration_tests" ]; then
  (exec 3<>/dev/tcp/127.0.0.1/5432) 2>/dev/null \
    || block "Postgres is not running, so integration tests can't run" "Start it with: docker compose up -d postgres"
  output=$(vitest integration) || block "integration tests failed" "$output"
fi
exit 0
