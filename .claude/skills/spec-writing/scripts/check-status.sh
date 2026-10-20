#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)

[ $# -eq 1 ] || { echo "usage: check-status.sh <feature>" >&2; exit 2; }
rc=0
for p in "spec:design" "detailed-design:detailed-design"; do
  label=${p%%:*}; f="$root/${p#*:}/features/$1.org"
  if [ -f "$f" ]; then
    s=$(grep -m1 '^:STATUS:' "$f" | sed 's/^:STATUS:[[:space:]]*//; s/[[:space:]]*$//' || true)
    echo "$label: ${s:-missing}"
    [ "$s" = accepted ] || rc=1
  else
    echo "$label: missing"; rc=1
  fi
done
exit $rc
