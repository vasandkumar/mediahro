#!/usr/bin/env bash
# Engine example integration tests (lane B1): one app launch per file, each
# attempt capped (simulator and emulator launches occasionally hang), one
# retry; mirrors tools/ci/run_integration.sh for the app.
# Usage: tool/run_example_tests.sh <flutter test args...>
# MEDIAHRO_TEST_CAP: seconds per attempt (default 1800, the suite is long).
set -uo pipefail
cd "$(dirname "$0")/../example"
cap="${MEDIAHRO_TEST_CAP:-1800}"
status=0
for f in integration_test/*_test.dart; do
  ok=0
  for attempt in 1 2; do
    if perl -e 'alarm shift; exec @ARGV' "$cap" flutter test "$f" --reporter expanded "$@"; then ok=1; break; fi
    echo "::warning::$f failed or timed out (attempt $attempt)"
  done
  [ $ok -eq 1 ] || status=1
done
exit $status
