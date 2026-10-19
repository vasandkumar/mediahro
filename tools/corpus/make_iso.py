"""Builds UDF disc images of the generated VIDEO_TS / BDMV folders (VID-001
ISO images) with pycdlib, an independent UDF writer, so the engine's own
UDF reader is checked against foreign images. Test media only; nothing is
shipped.

Usage: python tools/corpus/make_iso.py <generated-dir>
Exits 0 with a notice when pycdlib is not installed.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def build(src: Path, out: Path, label: str) -> None:
    import pycdlib  # noqa: PLC0415 - optional test-media dependency

    iso = pycdlib.PyCdlib()
    iso.new(interchange_level=3, udf="2.60", vol_ident=label)
    dirs = sorted({p.parent for p in src.rglob("*") if p.is_file()} | {src})
    for d in dirs:
        rel = d.relative_to(src)
        if rel.parts:
            udf = "/" + "/".join(rel.parts)
            iso9660 = "/" + "/".join(p.upper()[:8] for p in rel.parts)
            iso.add_directory(iso9660, udf_path=udf)
    for f in sorted(p for p in src.rglob("*") if p.is_file()):
        rel = f.relative_to(src)
        name = rel.parts[-1].upper()
        stem, _, ext = name.partition(".")
        iso_name = f"{stem[:8]}.{ext[:3]};1"
        parent = "/" + "/".join(p.upper()[:8] for p in rel.parts[:-1])
        iso.add_file(
            str(f),
            iso_path=(parent.rstrip("/") + "/" + iso_name),
            udf_path="/" + "/".join(rel.parts),
        )
    iso.write(str(out))
    iso.close()


def main(argv: list[str]) -> int:
    gen = Path(argv[1] if len(argv) > 1 else "test-media/generated")
    try:
        import pycdlib  # noqa: F401, PLC0415
    except ImportError:
        print("make-iso: pycdlib not installed; ISO images skipped")
        return 0
    manifest_path = gen / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    made = []
    for folder, label, kind in [("dvd", "MEDIAHRO_DVD", "dvd"), ("bluray", "MEDIAHRO_BD", "bluray")]:
        src = gen / folder
        if not src.is_dir():
            continue
        out = gen / f"{folder}.iso"
        build(src, out, label)
        made.append(out.name)
        source = next(i for i in manifest["items"] if i["file"] == folder)
        manifest["items"] = [i for i in manifest["items"] if i["file"] != out.name]
        manifest["items"].append({
            "file": out.name,
            "category": "disc-image",
            "ids": ["VID-001", "VID-007"],
            "expect": dict(source["expect"], image=True),
        })
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"make-iso: {', '.join(made) or 'nothing to do'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
