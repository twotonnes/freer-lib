#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)

[ $# -ge 1 ] || { echo "usage: changed-files.sh <allowed-path>..." >&2; exit 2; }
cd "$root"
out=""
while IFS= read -r line; do
  f=${line:3}; f=${f##* -> }; f=${f#\"}; f=${f%\"}
  ok=0
  for a in "$@"; do a=${a%/}; case "$f" in "$a"|"$a"/*) ok=1;; esac; done
  if [ $ok = 1 ]; then out+="$f"$'\n'; else out+="OUT: $f"$'\n'; fi
done < <(git status --porcelain --untracked-files=all)
printf '%s' "$out" | head -20
[ "$(printf '%s' "$out" | wc -l)" -le 20 ] || echo "... truncated (more than 20 lines)"
case "$out" in *OUT:*) exit 1;; esac
