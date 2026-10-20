#!/usr/bin/env bash
# Engine example integration tests (lane B1): one app launch per file, each
# attempt capped (simulator and emulator launches occasionally hang), one
# retry; mirrors tools/ci/run_integration.sh for the app.
# Usage: tool/run_example_tests.sh <flutter test args...>
# MEDIAHRO_TEST_CAP: seconds per attempt (default 1800, the suite is long).
# MEDIAHRO_ANDROID_WAIT=1: before each attempt, wait until the emulator is
# back on adb and booted (a failed VM-service start can drop it).
set -uo pipefail
cd "$(dirname "$0")/../example"
cap="${MEDIAHRO_TEST_CAP:-1800}"
status=0

wait_android() {
  [ "${MEDIAHRO_ANDROID_WAIT:-0}" = 1 ] || return 0
  if ! timeout 120 adb wait-for-device; then
    adb kill-server > /dev/null 2>&1
    adb start-server > /dev/null 2>&1
    timeout 180 adb wait-for-device || return 1
  fi
  for _ in $(seq 1 90); do
    [ "$(adb shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = 1 ] && return 0
    sleep 2
  done
  return 1
}

for f in integration_test/*_test.dart; do
  ok=0
  for attempt in 1 2; do
    wait_android || echo "::warning::emulator not ready before attempt $attempt"
    if perl -e 'alarm shift; exec @ARGV' "$cap" flutter test "$f" --reporter expanded "$@"; then ok=1; break; fi
    echo "::warning::$f failed or timed out (attempt $attempt)"
    sleep 10
  done
  [ $ok -eq 1 ] || status=1
done
exit $status
