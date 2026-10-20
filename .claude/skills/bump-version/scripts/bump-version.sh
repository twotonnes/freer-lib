#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)

level=${1:-}; entry=${2:-}
case "$level" in major|minor|patch|revision) ;; *) echo "usage: bump-version.sh <major|minor|patch|revision> [entry-file]" >&2; exit 2;; esac
[ -z "$entry" ] || [ -f "$entry" ] || { echo "entry file not found" >&2; exit 2; }
info="$root/info.rkt"
cl="$root/CHANGELOG.md"
[ -z "$entry" ] || [ -f "$cl" ] || { echo "CHANGELOG.md not found" >&2; exit 2; }
old=$(sed -n -E 's/^\(define version "([0-9]+\.[0-9]+\.[0-9]+)"\).*/\1/p' "$info" | head -1)
[ -n "$old" ] || { echo "version not found in info.rkt" >&2; exit 2; }
IFS=. read -r a b c <<<"$old"
case "$level" in
  major) new="$((a+1)).0.0";;
  minor) new="$a.$((b+1)).0";;
  *) new="$a.$b.$((c+1))";;
esac
[ -z "$entry" ] || grep -q '^## ' "$cl" || { echo "no ## heading in CHANGELOG.md" >&2; exit 2; }
sed -i -E "s/^(\(define version \")$old(\"\))/\1$new\2/" "$info"
if [ -n "$entry" ]; then
  awk -v ef="$entry" -v nv="$new" -v dt="$(date +%F)" '!d && /^## / { print "## " nv " (" dt ")"; print ""; while ((getline l < ef) > 0) print l; print ""; d=1 } { print }' "$cl" > "$cl.tmp"
  mv "$cl.tmp" "$cl"
fi
echo "$old -> $new"
"$root/.claude/skills/code-writing/scripts/test.sh"
