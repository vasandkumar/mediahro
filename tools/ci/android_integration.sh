#!/usr/bin/env bash
# Android integration tests inside the emulator runner; dumps logcat on failure.
set -uo pipefail
adb logcat -c || true
cd "$(dirname "$0")/../../app"
flutter test integration_test --flavor foss --dart-define=MEDIAHRO_FLAVOR=foss
status=$?
adb logcat -d > ../build/logcat.txt 2>/dev/null || true
exit $status
