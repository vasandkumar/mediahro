"""No telemetry, location or test library in a release build (docs/09, PRIV-004).

Static guard that runs in tools/check without Gradle: the Android app's build
file must keep excluding the Google Data Transport uploader, the Firebase
encoders it needs and the location client that Play Billing links, and the
store manifest must keep the Data Transport job and alarm removed.

The real proof is resolved by Gradle: `./gradlew :app:verifyReleaseClasspaths`
runs before every release build and fails on a banned library on the store,
direct, foss or enterprise release classpath. To scan `:app:dependencies`
output instead, pass the files: `check_classpath.py report.txt ...`.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app" / "android" / "app"

BANNED = [
    ("com.google.android.datatransport", "transport-backend-cct"),
    ("com.google.android.gms", "play-services-location"),
    ("com.google.android.gms", "play-services-places-placereport"),
    ("com.google.firebase", "firebase-encoders-json"),
    ("com.google.firebase", "firebase-encoders-proto"),
    ("junit", "junit"),
    ("org.hamcrest", "hamcrest-core"),
    ("org.hamcrest", "hamcrest-library"),
    ("org.hamcrest", "hamcrest-integration"),
]
# These come from Play Billing and must be excluded; junit/hamcrest come only from
# the profile-only integration_test plugin and are checked on the release classpaths.
MUST_EXCLUDE = BANNED[:5]

REMOVED_COMPONENTS = [
    "com.google.android.datatransport.runtime.scheduling.jobscheduling.JobInfoSchedulerService",
    "com.google.android.datatransport.runtime.scheduling.jobscheduling.AlarmManagerSchedulerBroadcastReceiver",
]


def scan_reports(paths: list[str]) -> list[str]:
    errors = []
    for name in paths:
        for n, line in enumerate(Path(name).read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            for group, module in BANNED:
                if re.search(rf"{re.escape(group)}:{re.escape(module)}:", line):
                    errors.append(f"{name}:{n}: {group}:{module} on a release classpath")
    return errors


def static_checks() -> list[str]:
    errors = []
    gradle = (APP / "build.gradle.kts").read_text(encoding="utf-8")
    for group, module in MUST_EXCLUDE:
        if not re.search(rf'exclude\(group = "{re.escape(group)}", module = "{re.escape(module)}"\)', gradle):
            errors.append(f"app/android/app/build.gradle.kts: {group}:{module} is no longer excluded")
    if "verifyReleaseClasspaths" not in gradle:
        errors.append("app/android/app/build.gradle.kts: verifyReleaseClasspaths is missing")
    manifest = (APP / "src" / "store" / "AndroidManifest.xml").read_text(encoding="utf-8")
    manifest = re.sub(r"<!--.*?-->", "", manifest, flags=re.DOTALL)
    for component in REMOVED_COMPONENTS:
        if not re.search(rf'android:name="{re.escape(component)}"\s+tools:node="remove"', manifest):
            errors.append(f"app/android/app/src/store/AndroidManifest.xml: {component} is no longer removed")
    return errors


def main() -> int:
    errors = scan_reports(sys.argv[1:]) if len(sys.argv) > 1 else static_checks()
    for e in errors:
        print(f"classpath: {e}", file=sys.stderr)
    print(f"classpath: {len(errors)} errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
