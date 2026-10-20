#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)

[ $# -eq 1 ] && [ -f "$1" ] || { echo "usage: check-case-names.sh <file>" >&2; exit 2; }
names=$(grep -n -o 'test-case[[:space:]]*"[^"]*"' "$1" | sed -E 's/^([0-9]+):test-case[[:space:]]*"(.*)"$/\1: \2/' || true)
[ -n "$names" ] || { echo "no test cases found" >&2; exit 2; }
bad=$(printf '%s\n' "$names" | grep -v -E '^[0-9]+: [^:]+: should .+ when .+$' || true)
[ -z "$bad" ] && exit 0
printf '%s\n' "$bad" | head -20
exit 1
