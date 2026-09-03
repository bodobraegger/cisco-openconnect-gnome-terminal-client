#!/bin/bash
# Runs every test. No display, no root, no VPN required.
set -uo pipefail
cd "$(dirname "$0")/.."

failed=0
for suite in tests/test_*.py; do
    echo "== $suite"
    python3 "$suite" 2>&1 | tail -3 || failed=1
done
for suite in tests/test_*.sh; do
    echo "== $suite"
    bash "$suite" || failed=1
done

echo
if (( failed == 0 )); then
    echo "ALL SUITES PASSED"
else
    echo "SOME SUITES FAILED"
fi
exit $failed
