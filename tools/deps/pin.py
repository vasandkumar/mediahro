"""Pin a mediahro-deps GitHub release in deps.lock.

Reads the release's SHA256SUMS, downloads every archive deps.lock lists a
target for, and only writes deps.lock when each download matches its
published digest. Targets the release does not contain are left as they are
unless --clear-missing is given. Owner: lane B4.

Usage: python tools/deps/pin.py TAG [--repository vasandkumar/mediahro-deps] [--clear-missing] [--no-download]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UA = {"User-Agent": "mediahro-deps-pin/1"}


def get(url: str) -> bytes:
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r:  # noqa: S310 - release URL
        return r.read()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("tag")
    ap.add_argument("--repository", default=None)
    ap.add_argument("--clear-missing", action="store_true", help="set targets absent from the release to null")
    ap.add_argument("--no-download", action="store_true", help="trust SHA256SUMS without re-hashing the archives")
    args = ap.parse_args()
    lock_path = ROOT / "deps.lock"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    repo = args.repository or lock.get("repository") or "vasandkumar/mediahro-deps"
    base = f"https://github.com/{repo}/releases/download/{args.tag}/"
    sums = {}
    for line in get(base + "SHA256SUMS").decode().splitlines():
        if line.strip():
            digest, name = line.split(maxsplit=1)
            sums[name.lstrip("*")] = digest
    for target in lock["archives"]:
        name = f"mediahro-deps-{target}.tar.gz"
        if name not in sums:
            if args.clear_missing:
                lock["archives"][target] = None
            print(f"pin: {target}: not in {args.tag}" + (" (cleared)" if args.clear_missing else " (kept)"))
            continue
        if not args.no_download:
            got = hashlib.sha256(get(base + name)).hexdigest()
            if got != sums[name]:
                print(f"pin: {name}: download {got} != SHA256SUMS {sums[name]}", file=sys.stderr)
                return 1
        lock["archives"][target] = {"url": base + name, "sha256": sums[name]}
        print(f"pin: {target} {sums[name]}")
    if "mediahro-deps-sources.tar" in sums:
        lock["sources"] = {"url": base + "mediahro-deps-sources.tar", "sha256": sums["mediahro-deps-sources.tar"]}
    lock["repository"], lock["release"] = repo, args.tag
    with open(lock_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(lock, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
