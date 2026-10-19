"""Stage libmpv into the engine plugin's Apple build folders (lane B1).

SwiftPM and CocoaPods only accept binaries inside the plugin, so the
xcframeworks are copied from .deps-cache/<target>/Frameworks (the
mediahro-deps archive pinned in deps.lock) or, until B4 publishes it, from
.deps-cache/bootstrap/<target>/Frameworks (ADR-004, tool/fetch_libmpv.py).
Android (Gradle) and Windows (CMake) read .deps-cache directly.

Usage: python packages/mediahro_engine/tool/stage_native.py ios|macos
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLUGIN = HERE.parent
CACHE = PLUGIN.parents[1] / ".deps-cache"


def stage(platform: str) -> int:
    target = f"{platform}-xcframeworks"
    candidates = [CACHE / target / "Frameworks", CACHE / target,
                  CACHE / "bootstrap" / target / "Frameworks"]
    for src in candidates:
        if src.is_dir() and any(src.glob("*.xcframework")):
            break
    else:
        print(f"stage-native: no {target} in .deps-cache; run tool/fetch_libmpv.py {target}",
              file=sys.stderr)
        return 1
    dest = PLUGIN / platform / "mediahro_engine" / "Frameworks"
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    for fw in sorted(src.glob("*.xcframework")):
        shutil.copytree(fw, dest / fw.name, symlinks=True)
    print(f"stage-native: {platform} <- {src}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("ios", "macos"):
        print(__doc__)
        sys.exit(2)
    sys.exit(stage(sys.argv[1]))
