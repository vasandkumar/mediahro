"""Fetch the mediahro-deps archives pinned in deps.lock and verify SHA-256.

Archives unpack to .deps-cache/<target>/ with `lib/`, `include/` and a
`manifest.json` read by tools/licence_scan. Owner: lane B4.

Usage: python tools/deps/fetch.py [--target android-arm64-v8a ...]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".deps-cache"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", action="append", default=[])
    args = ap.parse_args()
    lock = json.loads((ROOT / "deps.lock").read_text(encoding="utf-8"))
    if not lock.get("release"):
        print("deps: no mediahro-deps release pinned yet (M0 bootstrap); native features report libraryMissing")
        return 0
    targets = args.target or [t for t, v in lock["archives"].items() if v]
    for t in targets:
        entry = lock["archives"].get(t)
        if not entry:
            print(f"deps: {t} not pinned", file=sys.stderr)
            return 1
        dest = CACHE / t
        stamp = dest / ".sha256"
        if stamp.exists() and stamp.read_text().strip() == entry["sha256"]:
            continue
        archive = CACHE / f"{t}.tar.zst" if entry["url"].endswith(".zst") else CACHE / f"{t}.tar.gz"
        CACHE.mkdir(exist_ok=True)
        print(f"deps: fetching {t}")
        urllib.request.urlretrieve(entry["url"], archive)  # noqa: S310 - URL comes from the reviewed lockfile
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != entry["sha256"]:
            print(f"deps: SHA-256 mismatch for {t}: {digest}", file=sys.stderr)
            archive.unlink()
            return 1
        dest.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive) as tf:
            tf.extractall(dest, filter="data")
        stamp.write_text(digest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
