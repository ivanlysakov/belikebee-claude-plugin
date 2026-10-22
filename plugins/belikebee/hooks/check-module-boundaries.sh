#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit): blocks imports that break the module boundaries in ARCHITECTURE.md.
# Only the text being written is checked, so existing code never blocks an unrelated edit.
# Exit 2 blocks the tool call and shows stderr to Claude; exit 0 lets it through.
# Needs jq. Written for bash 3.2 (macOS /bin/bash) and BSD or GNU tools.

# Modules that may not import any other module, even through index.ts (.claude/rules/<name>.md).
NO_MODULE_IMPORTS=" identity "

input=$(cat)
file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input")
text=$(jq -r '.tool_input | .content // .new_string // ([.edits[]?.new_string] | join("\n"))' <<<"$input")

case "$file_path" in
  */node_modules/*) exit 0 ;;
  */src/*.ts | */src/*.tsx | */src/*.js | */src/*.jsx | */src/*.mjs) ;;
  *) exit 0 ;;
esac
[ -n "$text" ] || exit 0

# Works in the main checkout and in worktrees: everything after the last "/src/" is the in-app path.
from_rel=${file_path##*/src/}

# Resolves "." and ".." segments; prints "../" if the path leaves src/.
normalize() {
  local IFS=/ part out=()
  set -f
  for part in $1; do
    case "$part" in
      '' | .) ;;
      ..) [ ${#out[@]} -eq 0 ] && { set +f; echo "../"; return; }
          unset "out[$((${#out[@]} - 1))]" ;;
      *) out+=("$part") ;;
    esac
  done
  set +f
  echo "${out[*]}"
}

# "modules/billing/db/queries" -> area=modules module=billing deep=1
locate() {
  local rest
  area=${1%%/*}
  module="" deep=0
  if [ "$area" = modules ]; then
    rest=${1#modules/}
    module=${rest%%/*}
    rest=${rest#"$module"}
    rest=${rest#/}
    case "$rest" in '' | index | index.ts | index.tsx) ;; *) deep=1 ;; esac
  fi
}

locate "$from_rel"
from_area=$area from_module=$module

violations=""
specifiers=$(grep -oE "(^|[^[:alnum:]_\$.])(from|import|require)[[:space:]]*\(?[[:space:]]*[\"'][^\"']+[\"']" <<<"$text" \
  | sed -E "s/.*[\"']([^\"']+)[\"']$/\1/" | sort -u)

for spec in $specifiers; do
  case "$spec" in
    @/*) target=${spec#@/} ;;
    .*) target=$(normalize "$(dirname "$from_rel")/$spec")
        [ "$target" = "../" ] && continue ;;
    *) continue ;; # npm package
  esac

  locate "$target"
  cross_module=0
  [ "$area" = modules ] && [ "$module" != "$from_module" ] && cross_module=1

  if [ "$from_area" = shared ] && { [ "$area" = modules ] || [ "$area" = app ]; }; then
    violations+=$'\n'"- \"$spec\": src/shared must not import from src/modules or src/app."
  elif [ "$from_area" = modules ] && [ "$area" = app ]; then
    violations+=$'\n'"- \"$spec\": a module must not import from src/app."
  elif [ "$from_area" = modules ] && [ $cross_module = 1 ] && [[ "$NO_MODULE_IMPORTS" == *" $from_module "* ]]; then
    violations+=$'\n'"- \"$spec\": $from_module may not import other modules (.claude/rules/$from_module.md). Raise the dependency instead, or react to a domain event."
  elif [ $cross_module = 1 ] && { [ $deep = 1 ] || [[ "$spec" == .* ]]; }; then
    violations+=$'\n'"- \"$spec\": import other modules only through their public API: \"@/modules/$module\"."
  fi
done

if [ -n "$violations" ]; then
  echo "Module boundary violation in src/$from_rel (ARCHITECTURE.md, Dependency rules):$violations" >&2
  exit 2
fi
exit 0
