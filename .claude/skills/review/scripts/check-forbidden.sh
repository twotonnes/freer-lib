#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)

[ $# -ge 1 ] || { echo "usage: check-forbidden.sh <file>..." >&2; exit 2; }
out=""
for f in "$@"; do
  case "$f" in *.rkt) [ -f "$f" ] || { echo "file not found: $f" >&2; exit 2; };; *) continue;; esac
  out+=$(grep -n -E 'define/contract|provide/contract|->i([^a-zA-Z0-9-]|$)|\(->\*?([[:space:]]|\)|$)|contract-out' "$f" \
    | grep -v -E '^[0-9]+:[[:space:]]*;;' | sed "s|^|$f:|" || true)$'\n'
done
out=$(printf '%s' "$out" | sed '/^$/d')
[ -z "$out" ] && exit 0
printf '%s\n' "$out" | head -20
exit 1
