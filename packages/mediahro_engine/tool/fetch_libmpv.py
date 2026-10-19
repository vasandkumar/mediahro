"""Fetch the ADR-004 bootstrap libmpv for lane B1 (engine CI and local work).

Downloads each requested target from tool/bootstrap_libmpv.json, verifies its
SHA-256, and lays it out under .deps-cache/bootstrap/<target>/ with the same
lib/ / Frameworks/ structure as the mediahro-deps archives, so the plugin
builds and tests look in one place. Once deps.lock pins a mediahro-deps
release, .deps-cache/<target>/ wins and this script is unused.

Usage: python packages/mediahro_engine/tool/fetch_libmpv.py <target> [...]
       python packages/mediahro_engine/tool/fetch_libmpv.py --print-path <target>
"""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DEST = ROOT / ".deps-cache" / "bootstrap"


def _extract(archive: Path, into: Path) -> None:
    name = archive.name
    if name.endswith(".7z"):
        subprocess.run(["7z", "x", "-y", f"-o{into}", str(archive)], check=True,
                       stdout=subprocess.DEVNULL)
    elif name.endswith(".jar") or name.endswith(".zip"):
        with zipfile.ZipFile(archive) as z:
            z.extractall(into)
    else:
        with tarfile.open(archive) as t:
            t.extractall(into, filter="data")


def fetch(target: str, spec: dict) -> Path:
    out = DEST / target
    stamp = out / ".sha256"
    if stamp.exists() and stamp.read_text().strip() == spec["sha256"]:
        return out
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        archive = tmpdir / spec["url"].rsplit("/", 1)[1]
        print(f"bootstrap-libmpv: fetching {target}")
        urllib.request.urlretrieve(spec["url"], archive)  # noqa: S310 - pinned URL, verified below
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != spec["sha256"]:
            raise SystemExit(f"bootstrap-libmpv: SHA-256 mismatch for {target}: {digest}")
        raw = tmpdir / "raw"
        _extract(archive, raw)
        if out.exists():
            shutil.rmtree(out)
        out.mkdir(parents=True)
        for src, dst in spec["layout"].items():
            s = raw / src
            d = out / dst
            d.parent.mkdir(parents=True, exist_ok=True)
            if s.is_dir():
                shutil.copytree(s, d, symlinks=True, dirs_exist_ok=True)
            else:
                shutil.copy2(s, d)
        (out / "LICENCE-NOTE.txt").write_text(
            f"{spec['licence']}\nSource: {spec['url']}\nSHA-256: {spec['sha256']}\n",
            encoding="utf-8",
        )
        stamp.write_text(spec["sha256"])
    return out


def main(argv: list[str]) -> int:
    manifest = json.loads((HERE / "bootstrap_libmpv.json").read_text(encoding="utf-8"))
    targets = manifest["targets"]
    print_path = "--print-path" in argv
    names = [a for a in argv if not a.startswith("--")]
    if not names:
        print("targets: " + ", ".join(targets))
        return 2
    for name in names:
        if name not in targets:
            print(f"unknown target {name}", file=sys.stderr)
            return 2
        path = fetch(name, targets[name])
        if print_path:
            print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
