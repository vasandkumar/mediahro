"""Licence scan and SBOM (docs/09 §2, ADR-002).

Fails the build when:
  * any shipped Dart package is GPL (any version), third-party AGPL, or of
    unknown licence;
  * any native artefact in the mediahro-deps manifest is GPL, statically
    linked while LGPL, built with --enable-gpl / --enable-nonfree /
    -Dgpl=true, or is on the banned list.

Writes a CycloneDX 1.5 SBOM to build/sbom.cdx.json.

Usage: python tools/licence_scan/licence_scan.py [--deps-manifest PATH ...]
Owner: lane B4 (extends with Gradle and SwiftPM sources).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKSPACE_PACKAGES = {
    "mediahro", "mediahro_workspace", "mediahro_design", "mediahro_engine",
    "mediahro_ffi", "mediahro_servers", "mediahro_subtitles", "mediahro_tools",
}
ALLOWED = {
    "MIT", "BSD-2-Clause", "BSD-3-Clause", "BSD-3-Clause-Clear", "Apache-2.0", "ISC", "Zlib",
    "MPL-1.1", "MPL-2.0", "CDDL-1.0", "curl", "Unlicense", "0BSD", "BSL-1.0", "Public-Domain",
    "LGPL-2.1-or-later", "LGPL-2.1-only", "LGPL-3.0-or-later", "OFL-1.1",
}
LGPL = {"LGPL-2.1-or-later", "LGPL-2.1-only", "LGPL-3.0-or-later"}
BANNED_NATIVE = re.compile(r"exiv2|x264|x265|rubberband|libdvdcss|postproc|smbclient|libcdio|frei0r|mutagen", re.I)
GPL_FLAGS = ("--enable-gpl", "--enable-nonfree", "--enable-version3", "-Dgpl=true")

# Ordered: most specific first.
SIGNATURES: list[tuple[str, re.Pattern[str]]] = [
    ("AGPL-3.0", re.compile(r"GNU AFFERO GENERAL PUBLIC LICENSE", re.I)),
    ("LGPL-3.0-or-later", re.compile(r"GNU LESSER GENERAL PUBLIC LICENSE\s+Version 3", re.I)),
    ("LGPL-2.1-or-later", re.compile(r"GNU LESSER GENERAL PUBLIC LICENSE\s+Version 2\.1", re.I)),
    ("GPL", re.compile(r"GNU GENERAL PUBLIC LICENSE", re.I)),
    ("MPL-2.0", re.compile(r"Mozilla Public License,? (Version|v\.?) ?2\.0", re.I)),
    ("Apache-2.0", re.compile(r"Apache License,?\s+Version 2\.0", re.I)),
    ("BSD-3-Clause", re.compile(r"Neither the name of .{0,120}? nor the names of its\s+contributors", re.I | re.S)),
    ("BSD-2-Clause", re.compile(r"Redistributions in binary form must reproduce the above copyright", re.I)),
    ("MIT", re.compile(r"Permission is hereby granted, free of charge, to any person obtaining", re.I)),
    ("ISC", re.compile(r"Permission to use, copy, modify, and/or distribute this software for any", re.I)),
    ("Zlib", re.compile(r"This software is provided 'as-is', without any express or implied", re.I)),
    ("Unlicense", re.compile(r"This is free and unencumbered software released into the public domain", re.I)),
]


def classify(text: str) -> str:
    for spdx, pat in SIGNATURES:
        if pat.search(text):
            return spdx
    return "UNKNOWN"


def shipped_pub_packages() -> dict[str, str]:
    """Non-dev transitive dependencies of the app → version."""
    out = subprocess.run(
        ["dart", "pub", "deps", "--json"], cwd=ROOT / "app", capture_output=True, text=True, check=True,
        shell=sys.platform == "win32",
    ).stdout
    data = json.loads(out)
    by_name = {p["name"]: p for p in data["packages"]}
    roots = [p for p in data["packages"] if p["name"] == "mediahro"]
    seen: dict[str, str] = {}
    # Root and workspace members list dev deps in "dependencies"; use the
    # direct (non-dev) list for them.
    stack = list(roots[0]["directDependencies"])
    while stack:
        name = stack.pop()
        if name in seen or name not in by_name:
            continue
        pkg = by_name[name]
        seen[name] = f'{pkg.get("version", "")}|{pkg.get("source", "")}'
        stack.extend(pkg.get("directDependencies", pkg.get("dependencies", [])))
    return seen


def package_roots() -> dict[str, Path]:
    cfg = json.loads((ROOT / ".dart_tool" / "package_config.json").read_text(encoding="utf-8"))
    roots = {}
    for p in cfg["packages"]:
        uri = p["rootUri"]
        if uri.startswith("file:///"):
            path = Path(re.sub(r"^file:///", "", uri).replace("%20", " "))
            if not path.drive and sys.platform != "win32":
                path = Path("/" + str(path))
        else:
            path = (ROOT / ".dart_tool" / uri).resolve()
        roots[p["name"]] = path
    return roots


def scan_pub(errors: list[str]) -> list[dict]:
    components = []
    roots = package_roots()
    for name, tagged in sorted(shipped_pub_packages().items()):
        version, source = tagged.split("|")
        if name in WORKSPACE_PACKAGES:
            continue
        root = roots.get(name)
        if root is None or source == "sdk":  # Flutter SDK packages: BSD-3-Clause (Flutter LICENSE).
            spdx = "BSD-3-Clause"
        else:
            lic = next((root / n for n in ("LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING") if (root / n).exists()), None)
            spdx = classify(lic.read_text(encoding="utf-8", errors="replace")) if lic else "UNKNOWN"
        if spdx not in ALLOWED:
            errors.append(f"pub:{name}@{version}: licence {spdx} is not allowed")
        components.append({"type": "library", "name": name, "version": version, "purl": f"pkg:pub/{name}@{version}",
                           "licenses": [{"license": {"id": spdx}}] if spdx != "UNKNOWN" else []})
    return components


def scan_native(manifests: list[Path], errors: list[str]) -> list[dict]:
    """mediahro-deps manifest schema: {"artefacts": [{"name","version","license","linking","configure"}]}."""
    components = []
    for m in manifests:
        data = json.loads(m.read_text(encoding="utf-8"))
        for a in data.get("artefacts", []):
            name, spdx, linking = a["name"], a["license"], a.get("linking", "dynamic")
            flags = " ".join(a.get("configure", []))
            if BANNED_NATIVE.search(name):
                errors.append(f"native:{name}: banned component (docs/09 §2)")
            if spdx.startswith("GPL") or spdx.startswith("AGPL"):
                errors.append(f"native:{name}: {spdx} is never shipped (ADR-002)")
            if spdx in LGPL and linking != "dynamic":
                errors.append(f"native:{name}: LGPL must be dynamically linked, found {linking}")
            for flag in GPL_FLAGS:
                if flag in flags:
                    errors.append(f"native:{name}: configured with {flag}")
            components.append({"type": "library", "name": name, "version": a.get("version", ""),
                               "licenses": [{"license": {"id": spdx}}],
                               "properties": [{"name": "mediahro:linking", "value": linking},
                                              {"name": "mediahro:configure", "value": flags}]})
    return components


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--deps-manifest", action="append", type=Path, default=[])
    ap.add_argument("--require-native", action="store_true", help="fail when no native manifest is supplied (M0 exit onwards)")
    args = ap.parse_args()
    manifests = args.deps_manifest or sorted((ROOT / ".deps-cache").glob("*/manifest.json"))
    errors: list[str] = []
    components = scan_pub(errors)
    if manifests:
        components += scan_native(manifests, errors)
    elif args.require_native:
        errors.append("no mediahro-deps manifest found (.deps-cache/<platform>/manifest.json)")
    sbom = {"bomFormat": "CycloneDX", "specVersion": "1.5", "version": 1,
            "metadata": {"component": {"type": "application", "name": "mediahro", "licenses": [{"license": {"id": "AGPL-3.0-or-later"}}]}},
            "components": components}
    out = ROOT / "build" / "sbom.cdx.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(sbom, indent=2), encoding="utf-8")
    for e in errors:
        print(f"licence: {e}", file=sys.stderr)
    print(f"licence: {len(components)} components, {len(errors)} errors; SBOM at {out.relative_to(ROOT)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
