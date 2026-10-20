#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)

[ $# -eq 1 ] && [ -f "$1" ] || { echo "usage: check-type-comments.sh <file.rkt>" >&2; exit 2; }
out=$(awk '
  /^\(module\+ test/ { intest=1 }
  intest { if ($0 ~ /^\)/ || $0 ~ /^\(/ && $0 !~ /^\(module\+ test/) intest=0; else next }
  /^\((define|define-values|define-syntax|define-syntax-rule)[ \t]/ {
    ok = (p1 ~ /^;; Type:/) || (p1 ~ /^;; Impure:/ && p2 ~ /^;; Type:/)
    if (!ok) print NR ": " $0
  }
  { p2=p1; p1=$0 }
' "$1")
[ -z "$out" ] && exit 0
printf '%s\n' "$out" | head -20
exit 1
