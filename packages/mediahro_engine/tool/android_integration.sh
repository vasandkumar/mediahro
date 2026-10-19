#!/usr/bin/env bash
# Engine example integration tests inside the emulator runner (lane B1);
# dumps logcat on failure.
set -uo pipefail
adb logcat -c || true
cd "$(dirname "$0")/../example"
flutter test integration_test --reporter expanded
status=$?
mkdir -p ../../../build
adb logcat -d > ../../../build/engine-logcat.txt 2>/dev/null || true
exit $status
