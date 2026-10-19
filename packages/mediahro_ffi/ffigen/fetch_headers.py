#!/usr/bin/env python3
"""Fetch upstream source tarballs for lane B2's ffigen inputs (headers only).

Until lane B4 publishes the mediahro-deps archives (whose headers land in
.deps-cache/<platform>/include), ffigen reads headers from the upstream
releases pinned here, matching mediahro-deps/versions.json. Every tarball is
verified against its SHA-256 before extraction; only include directories are
kept, under .deps-cache/headers/<lib>/.

    python packages/mediahro_ffi/ffigen/fetch_headers.py [--from DIR]

--from DIR uses tarballs already downloaded into DIR (same file names).
"""
import argparse
import hashlib
import io
import pathlib
import shutil
import sys
import tarfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / ".deps-cache" / "headers"

# name: (version, file, url, sha256, include dir inside the tarball[, only these headers])
PINS = {
    "libsmb2": ("6.2", "libsmb2-6.2.tar.gz",
                "https://github.com/sahlberg/libsmb2/archive/refs/tags/libsmb2-6.2.tar.gz",
                "8e1f9efc6b2e0f6546f0fe121ac0ddf4fc2f0908ae5a6bd1f185be7c9e0bcbb3",
                "include"),
    "libnfs": ("6.0.2", "libnfs-6.0.2.tar.gz",
               "https://github.com/sahlberg/libnfs/archive/refs/tags/libnfs-6.0.2.tar.gz",
               "4e5459cc3e0242447879004e9ad28286d4d27daa42cbdcde423248fad911e747",
               "include"),
    "curl": ("8.23.0", "curl-8.23.0.tar.xz",
             "https://curl.se/download/curl-8.23.0.tar.xz",
             "8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5",
             "include"),
    "libarchive": ("3.8.10", "libarchive-3.8.10.tar.xz",
                   "https://github.com/libarchive/libarchive/releases/download/v3.8.10/libarchive-3.8.10.tar.xz",
                   "56cad765459d5ee25a3b761f90c47d99379d28297fbfb72d908880d6b875fb96",
                   "libarchive"),
    "libebur128": ("1.2.6", "libebur128-1.2.6.tar.gz",
                   "https://github.com/jiixyj/libebur128/archive/refs/tags/v1.2.6.tar.gz",
                   "baa7fc293a3d4651e244d8022ad03ab797ca3c2ad8442c43199afe8059faa613",
                   "ebur128", ["ebur128.h"]),
    "chromaprint": ("1.6.2", "chromaprint-1.6.2.tar.gz",
                    "https://github.com/acoustid/chromaprint/releases/download/v1.6.2/chromaprint-1.6.2.tar.gz",
                    "d54ada62c16b2db396d3251ec54fc7a58909c163131a1cfcf7fa6407dbc14360",
                    "src", ["chromaprint.h"]),
    "libssh2": ("1.11.1", "libssh2-1.11.1.tar.xz",
                "https://libssh2.org/download/libssh2-1.11.1.tar.xz",
                "9954cb54c4f548198a7cbebad248bdc87dd64bd26185708a294b2b50771e3769",
                "include", ["libssh2.h", "libssh2_sftp.h"]),
    "uchardet": ("0.0.8", "uchardet-0.0.8.tar.xz",
                 "https://www.freedesktop.org/software/uchardet/releases/uchardet-0.0.8.tar.xz",
                 "e97a60cfc00a1c147a674b097bb1422abd9fa78a2d9ce3f3fdcc2e78a34ac5f0",
                 "src", ["uchardet.h"]),
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="src", type=pathlib.Path)
    args = ap.parse_args()
    for name, (version, file, url, sha, inc, *only) in PINS.items():
        keep = set(only[0]) if only else None
        dest = OUT / name
        stamp = dest / ".version"
        if stamp.exists() and stamp.read_text() == version:
            continue
        data = (args.src / file).read_bytes() if args.src else urllib.request.urlopen(url, timeout=60).read()
        digest = hashlib.sha256(data).hexdigest()
        if digest != sha:
            print(f"fetch_headers: {file}: sha256 {digest} != pinned {sha}", file=sys.stderr)
            return 1
        shutil.rmtree(dest, ignore_errors=True)
        dest.mkdir(parents=True)
        with tarfile.open(fileobj=io.BytesIO(data)) as tar:
            top = tar.getmembers()[0].name.split("/")[0]
            prefix = f"{top}/{inc}/"
            for m in tar.getmembers():
                # Headers only, no links, no path escapes.
                if not m.isfile() or not m.name.startswith(prefix) or not m.name.endswith(".h"):
                    continue
                rel = pathlib.PurePosixPath(m.name[len(prefix):])
                if rel.is_absolute() or ".." in rel.parts:
                    continue
                if keep is not None and str(rel) not in keep:
                    continue
                target = dest / "include" / pathlib.Path(*rel.parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(tar.extractfile(m).read())
        stamp.write_text(version)
        print(f"fetch_headers: {name} {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
