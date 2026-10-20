#!/usr/bin/env bash
# Engine example integration tests inside the emulator runner (lane B1);
# dumps logcat on failure.
set -uo pipefail
adb logcat -c || true
here="$(cd "$(dirname "$0")" && pwd)"
"$here/run_example_tests.sh"
status=$?
cd "$here/../example"
mkdir -p ../../../build
adb logcat -d > ../../../build/engine-logcat.txt 2>/dev/null || true
exit $status
