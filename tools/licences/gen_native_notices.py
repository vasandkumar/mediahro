"""Builds the native-library notices the About screen shows (CORE-013).

Reads the mediahro-deps archives unpacked by `tools/deps/fetch.py`
(`.deps-cache/<target>/manifest.json` and `licenses/<name>.txt`) and writes
`app/assets/licences/native_libraries.json`: every shipped library with its
version, licence, linking, source URL and checksum, patches, the exact
configure line for the ones the licence requires it for (FFmpeg, mpv,
libplacebo), and the licence texts (identical texts stored once). The pinned
release and the source archive come from `deps.lock`.

Run it after `tools/deps/pin.py` changes the pin:

    python tools/deps/fetch.py
    python tools/licences/gen_native_notices.py

`--check` fails when the committed file is out of date (CI and the Dart test).
Owner: lane C4a (CORE-013).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".deps-cache"
LOCK = ROOT / "deps.lock"
OUT = ROOT / "app" / "assets" / "licences" / "native_libraries.json"

# Libraries whose licence (LGPL) asks for the configure line to be published.
SHOW_CONFIGURE = {"ffmpeg", "mpv", "libplacebo"}
# The licence families that must never appear in a shipped component.
FORBIDDEN = ("AGPL", "GPL-2.0-only", "GPL-3.0-only")
SCHEMA = 1


def platform_of(target: str) -> str:
    return target.split("-")[0]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")


def build(targets: list[str], cache: Path = CACHE, lock_path: Path = LOCK) -> dict:
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    texts: dict[str, str] = {}
    components: dict[tuple[str, str], dict] = {}
    for target in targets:
        base = cache / target
        manifest = json.loads((base / "manifest.json").read_text(encoding="utf-8"))
        if manifest.get("target") != target:
            raise SystemExit(f"{target}: manifest names {manifest.get('target')}")
        for a in manifest["artefacts"]:
            name, version = a["name"], a["version"]
            licence = a["license"]
            if any(bad in licence for bad in FORBIDDEN):
                raise SystemExit(f"{name} {version}: licence {licence} is not allowed")
            txt = base / "licenses" / f"{name}.txt"
            if not txt.exists():
                raise SystemExit(f"{name}: no licence text in {txt}")
            text = read_text(txt)
            text_id = hashlib.sha256(text.encode("utf-8")).hexdigest()[:12]
            texts[text_id] = text
            key = (name, version)
            c = components.get(key)
            if c is None:
                src = a.get("source", {})
                c = components[key] = {
                    "name": name,
                    "version": version,
                    "license": licence,
                    "linking": a["linking"],
                    "sourceUrl": src.get("url"),
                    "sourceSha256": src.get("sha256"),
                    "patches": [
                        {"file": p["file"], "sha256": p["sha256"]}
                        for p in src.get("patches", [])
                    ],
                    "textId": text_id,
                    "platforms": [],
                }
                if name in SHOW_CONFIGURE:
                    c["configure"] = a["configure"]
            if platform_of(target) not in c["platforms"]:
                c["platforms"].append(platform_of(target))
    return {
        "schema": SCHEMA,
        "repository": lock["repository"],
        "release": lock["release"],
        "releaseUrl": f"https://github.com/{lock['repository']}/releases/tag/{lock['release']}",
        "sources": lock.get("sources"),
        "components": sorted(components.values(), key=lambda c: c["name"]),
        "texts": dict(sorted(texts.items())),
    }


def render(doc: dict) -> str:
    return json.dumps(doc, indent=1, ensure_ascii=False, sort_keys=False) + "\n"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--target", action="append", help="deps target; default: every unpacked Android target")
    p.add_argument("--out", type=Path, default=OUT)
    p.add_argument("--check", action="store_true", help="fail if --out differs from the generated data")
    args = p.parse_args(argv)
    targets = args.target or sorted(
        d.name for d in CACHE.glob("android-*") if (d / "manifest.json").exists()
    )
    if not targets:
        print("licences: no unpacked deps in .deps-cache (run tools/deps/fetch.py)", file=sys.stderr)
        return 1
    text = render(build(targets, cache=CACHE, lock_path=LOCK))
    if args.check:
        have = args.out.read_text(encoding="utf-8") if args.out.exists() else ""
        if have != text:
            print(f"licences: {args.out} is out of date; run tools/licences/gen_native_notices.py", file=sys.stderr)
            return 1
        print(f"licences: {args.out.name} is up to date")
        return 0
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text, encoding="utf-8", newline="\n")
    n = len(json.loads(text)["components"])
    print(f"licences: wrote {args.out.relative_to(ROOT)} ({n} libraries, {len(text) // 1024} KiB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
