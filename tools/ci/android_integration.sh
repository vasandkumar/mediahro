#!/usr/bin/env bash
# Android integration tests inside the emulator runner: one app launch per
# file, one retry (the Dart Development Service occasionally fails to start
# on the emulator; --no-dds is not an option: it breaks the golden-file stream), logcat captured.
set -uo pipefail
cd "$(dirname "$0")/../../app"
mkdir -p ../build
status=0
for f in integration_test/*_test.dart; do
  ok=0
  for attempt in 1 2; do
    adb logcat -c || true
    if flutter test "$f" --flavor foss --dart-define=MEDIAHRO_FLAVOR=foss; then ok=1; fi
    adb logcat -d >> ../build/logcat.txt 2>/dev/null || true
    [ $ok -eq 1 ] && break
    echo "::warning::$f failed (attempt $attempt)"
  done
  [ $ok -eq 1 ] || status=1
done
exit $status
