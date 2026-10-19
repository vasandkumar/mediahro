#!/usr/bin/env bash
# Android integration tests inside the emulator runner: one app launch per
# file (a second launch in one invocation loses the Dart VM service), logcat
# captured for every run.
set -uo pipefail
cd "$(dirname "$0")/../../app"
mkdir -p ../build
status=0
for f in integration_test/*_test.dart; do
  adb logcat -c || true
  flutter test "$f" --flavor foss --dart-define=MEDIAHRO_FLAVOR=foss || status=1
  adb logcat -d >> ../build/logcat.txt 2>/dev/null || true
done
exit $status
