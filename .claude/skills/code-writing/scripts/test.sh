#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)

cd "$root"
rc=0
make test > /tmp/freer-test.log 2>&1 || rc=$?
echo "exit $rc"
grep -E '^(FAILURE|ERROR)|^(name|location|expected|actual):|^make.*Error|: error:' /tmp/freer-test.log | head -18 || true
exit $rc
