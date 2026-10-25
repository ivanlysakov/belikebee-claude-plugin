#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit): blocks raw colors and text sizes in .tsx/.jsx markup under src/.
# Values belong in the palette of src/app/globals.css, markup uses roles (bg-primary, type-title).
# Only the text being written is checked, so existing code never blocks an unrelated edit.
# Exit 2 blocks the tool call and shows stderr to Claude; exit 0 lets it through.
# Needs jq. Written for bash 3.2 (macOS /bin/bash) and BSD or GNU tools.

input=$(cat)
file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input")
text=$(jq -r '.tool_input | .content // .new_string // ([.edits[]?.new_string] | join("\n"))' <<<"$input")

case "$file_path" in
  */node_modules/*) exit 0 ;;
  */src/*.tsx | */src/*.jsx) ;;
  *) exit 0 ;;
esac
[ -n "$text" ] || exit 0

colors="slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose|black|white"
utilities="bg|text|border|ring|fill|stroke|from|via|to|outline|decoration|shadow|accent|caret|divide|placeholder"

# label|trim|ERE. Boundary characters around a match are cut from the report; trim=1 also cuts
# the trailing boundary for rules that end with one.
rules="hex color|1|(^|[^&[:alnum:]])#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})([^[:alnum:]_-]|\$)
color function|0|(^|[^[:alnum:]_-])(oklch|oklab|lch|lab|rgba?|hsla?|color-mix)\(
Tailwind palette color|0|(^|[^[:alnum:]_-])($utilities)-($colors)(-[0-9]{2,3})?
arbitrary color|0|-\[(#|oklch|oklab|rgb|hsl|color-mix|var\()
arbitrary text size|0|(^|[^[:alnum:]_-])text-\[[0-9.]+(px|rem|em)\]"

violations=""
while IFS='|' read -r label trim pattern; do
  found=$(grep -oE -e "$pattern" <<<"$text" | sed -E 's/^[^[:alnum:]#-]//' \
    | if [ "$trim" = 1 ]; then sed -E 's/[^[:alnum:]]$//'; else cat; fi | sort -u | tr '\n' ' ')
  [ -n "$found" ] && violations+=$'\n'"- $label: $found"
done <<<"$rules"

if [ -n "$violations" ]; then
  echo "Raw design values in ${file_path##*/src/} (docs/design/design-system.md):$violations
Use a role utility instead (bg-primary, text-muted-foreground, type-title, ...). If no role fits, add the value to the palette in src/app/globals.css, point a role at it, and use the role." >&2
  exit 2
fi
exit 0
