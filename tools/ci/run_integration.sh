#!/usr/bin/env bash
# Desktop/simulator integration tests: one app launch per file, each attempt
# capped at 15 minutes (simulator launches occasionally hang), one retry.
# Usage: tools/ci/run_integration.sh <flutter test args...>
set -uo pipefail
cd "$(dirname "$0")/../../app"
status=0
for f in integration_test/*_test.dart; do
  # Profile-mode budgets live in *_perf_test.dart and run only in the perf job.
  case "$f" in *_perf_test.dart) continue;; esac
  ok=0
  for attempt in 1 2; do
    if perl -e 'alarm shift; exec @ARGV' 900 flutter test "$f" "$@"; then ok=1; break; fi
    echo "::warning::$f failed or timed out (attempt $attempt)"
  done
  [ $ok -eq 1 ] || status=1
done
exit $status
