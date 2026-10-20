#!/usr/bin/env bash
# Engine example integration tests inside the emulator runner (lane B1);
# one retry per file after the emulator is back on adb (no --no-dds: it
# breaks the golden-file stream); dumps logcat.
set -uo pipefail
adb logcat -c || true
here="$(cd "$(dirname "$0")" && pwd)"
MEDIAHRO_ANDROID_WAIT=1 "$here/run_example_tests.sh"
status=$?
cd "$here/../example"
mkdir -p ../../../build
adb logcat -d > ../../../build/engine-logcat.txt 2>/dev/null || true
exit $status
