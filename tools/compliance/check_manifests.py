"""Store-policy guard for platform manifests (docs/07 §1, §3.1).

Fails when the Android manifest requests MANAGE_EXTERNAL_STORAGE or any
location permission, when RECEIVE_BOOT_COMPLETED appears outside the
enterprise source set, or when an Apple Info.plist enables tracking or
UIRequiresFullScreen.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FORBIDDEN_ANDROID = [
    "android.permission.MANAGE_EXTERNAL_STORAGE",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_BACKGROUND_LOCATION",
    "android.permission.READ_CONTACTS",
    "com.google.android.gms.permission.AD_ID",
]


def main() -> int:
    errors = []
    for m in (ROOT / "app" / "android" / "app" / "src").glob("*/AndroidManifest.xml"):
        text = m.read_text(encoding="utf-8")
        for perm in FORBIDDEN_ANDROID:
            if perm in text:
                errors.append(f"{m.relative_to(ROOT)}: {perm} is not allowed")
        if "RECEIVE_BOOT_COMPLETED" in text and m.parent.name != "enterprise":
            errors.append(f"{m.relative_to(ROOT)}: RECEIVE_BOOT_COMPLETED only in the enterprise flavour")
    for plist in [ROOT / "app" / "ios" / "Runner" / "Info.plist", ROOT / "app" / "macos" / "Runner" / "Info.plist"]:
        text = plist.read_text(encoding="utf-8")
        if "NSUserTrackingUsageDescription" in text:
            errors.append(f"{plist.relative_to(ROOT)}: no tracking (docs/07 §2.1 5.1.2)")
        if re.search(r"<key>UIRequiresFullScreen</key>\s*<true/>", text):
            errors.append(f"{plist.relative_to(ROOT)}: UIRequiresFullScreen breaks iPad windowing (CORE-010)")
    for e in errors:
        print(f"manifest: {e}", file=sys.stderr)
    print(f"manifest: {len(errors)} errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
