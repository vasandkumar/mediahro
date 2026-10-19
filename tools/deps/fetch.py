"""Fetch the mediahro-deps archives pinned in deps.lock and verify SHA-256.

Archives unpack to .deps-cache/<target>/ with `lib/`, `include/`,
`licenses/` and a `manifest.json` read by tools/licence_scan. Nothing is
extracted before its SHA-256 matches deps.lock; the archive's manifest must
name the same target. Owner: lane B4.

Usage: python tools/deps/fetch.py [--target android-arm64-v8a ...] [--platform android] [--force]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import tarfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".deps-cache"
UA = {"User-Agent": "mediahro-deps-fetch/1"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url: str, dest: Path, attempts: int = 4) -> None:
    tmp = dest.with_name(dest.name + ".part")
    for n in range(1, attempts + 1):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:  # noqa: S310 - URL comes from the reviewed lockfile
                shutil.copyfileobj(r, f, 1 << 20)
            tmp.replace(dest)
            return
        except OSError as e:
            if n == attempts:
                raise
            print(f"deps: retry {n} for {url}: {e}", file=sys.stderr)
            time.sleep(3 * n)


def safe_extract(archive: Path, dest: Path) -> None:
    with tarfile.open(archive) as tf:
        if hasattr(tarfile, "data_filter"):
            tf.extractall(dest, filter="data")
            return
        root = dest.resolve()
        for m in tf.getmembers():  # Python without extraction filters: refuse anything leaving dest.
            target = (dest / m.name).resolve()
            if not str(target).startswith(str(root)) or m.issym() or m.islnk() or m.isdev():
                raise SystemExit(f"deps: unsafe archive member {m.name}")
        tf.extractall(dest)  # noqa: S202 - members checked above


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", action="append", default=[])
    ap.add_argument("--platform", action="append", default=[], help="android, ios, macos, windows (target prefix)")
    ap.add_argument("--force", action="store_true", help="re-download and re-extract even when the cache matches")
    args = ap.parse_args()
    lock = json.loads((ROOT / "deps.lock").read_text(encoding="utf-8"))
    if not lock.get("release"):
        print("deps: no mediahro-deps release pinned yet (M0 bootstrap); native features report libraryMissing")
        return 0
    targets = args.target or [t for t, v in lock["archives"].items()
                              if v and (not args.platform or t.split("-")[0] in args.platform)]
    for t in targets:
        entry = lock["archives"].get(t)
        if not entry:
            print(f"deps: {t} is not pinned in deps.lock (release {lock['release']})", file=sys.stderr)
            return 1
        dest = CACHE / t
        stamp = dest / ".sha256"
        if not args.force and stamp.exists() and stamp.read_text().strip() == entry["sha256"]:
            print(f"deps: {t} up to date ({lock['release']})")
            continue
        archive = CACHE / Path(entry["url"]).name
        CACHE.mkdir(exist_ok=True)
        if args.force or not archive.exists() or sha256(archive) != entry["sha256"]:
            print(f"deps: fetching {t} from {entry['url']}")
            download(entry["url"], archive)
        digest = sha256(archive)
        if digest != entry["sha256"]:
            print(f"deps: SHA-256 mismatch for {t}: got {digest}, deps.lock has {entry['sha256']}", file=sys.stderr)
            archive.unlink()
            return 1
        shutil.rmtree(dest, ignore_errors=True)
        dest.mkdir(parents=True)
        safe_extract(archive, dest)
        manifest = json.loads((dest / "manifest.json").read_text(encoding="utf-8"))
        if manifest.get("target") != t:
            print(f"deps: {archive.name} contains target {manifest.get('target')}, expected {t}", file=sys.stderr)
            return 1
        stamp.write_text(digest)
        print(f"deps: {t} ok ({len(manifest.get('artefacts', []))} libraries, release {lock['release']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
