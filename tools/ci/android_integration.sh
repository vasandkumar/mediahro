#!/usr/bin/env bash
# Android integration tests inside the emulator runner: one app launch per
# file, no Dart Development Service (it fails to attach on the emulator
# intermittently), one retry, logcat captured for every attempt.
set -uo pipefail
cd "$(dirname "$0")/../../app"
mkdir -p ../build
status=0
for f in integration_test/*_test.dart; do
  ok=0
  for attempt in 1 2; do
    adb logcat -c || true
    if flutter test "$f" --no-dds --flavor foss --dart-define=MEDIAHRO_FLAVOR=foss; then ok=1; fi
    adb logcat -d >> ../build/logcat.txt 2>/dev/null || true
    [ $ok -eq 1 ] && break
    echo "::warning::$f failed (attempt $attempt)"
  done
  [ $ok -eq 1 ] || status=1
done
exit $status
