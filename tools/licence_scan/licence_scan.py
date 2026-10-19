"""Licence scan and SBOM (docs/09 §2, ADR-002).

Fails the build when:
  * any shipped Dart package is GPL (any version), third-party AGPL, or of
    unknown licence;
  * any Gradle (Android), SwiftPM or CocoaPods (Apple) dependency is GPL
    without an exception, of unknown licence, or proprietary outside the
    `store` flavour (docs/09 §2: proprietary SDKs only in store flavours);
  * any native artefact in the mediahro-deps manifest is GPL, statically
    linked while LGPL, built with --enable-gpl / --enable-nonfree /
    -Dgpl=true, on the banned list, or has GPL-only sources compiled into it
    (mediahro-deps scripts/source_scan.py records them per library);
  * any native binary (.so / .dll / .dylib / framework) carries a GPL-only
    build marker (FFmpeg licence or configuration string, mpv -Dgpl=true) or
    identifies a banned library (x264, x265, rubberband, libdvdcss, Exiv2,
    OpenSSL / BoringSSL, ...).

Writes a CycloneDX 1.5 SBOM to build/sbom.cdx.json.

Usage: python tools/licence_scan/licence_scan.py [--deps-manifest PATH ...] [--require-native]
           [--no-gradle] [--gradle-deps FLAVOR=FILE ...] [--no-apple] [--online]
Owner: lane B4.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WORKSPACE_PACKAGES = {
    "mediahro", "mediahro_workspace", "mediahro_design", "mediahro_engine",
    "mediahro_ffi", "mediahro_servers", "mediahro_subtitles", "mediahro_tools",
}
ALLOWED = {
    "MIT", "BSD-2-Clause", "BSD-3-Clause", "BSD-3-Clause-Clear", "Apache-2.0", "ISC", "Zlib",
    "MPL-1.1", "MPL-2.0", "CDDL-1.0", "curl", "Unlicense", "0BSD", "BSL-1.0", "Public-Domain",
    "LGPL-2.1-or-later", "LGPL-2.1-only", "LGPL-3.0-or-later", "OFL-1.1",
    "FTL", "libtiff", "IJG", "bzip2-1.0.6", "EPL-1.0", "EPL-2.0", "Unicode-3.0", "Unicode-DFS-2016",
}
# SPDX exceptions that make a GPL component distributable as part of a non-GPL work.
ALLOWED_EXCEPTIONS = {"Bison-exception-2.2", "Classpath-exception-2.0", "GCC-exception-3.1", "Autoconf-exception-3.0",
                      "LLVM-exception"}
LGPL = {"LGPL-2.1-or-later", "LGPL-2.1-only", "LGPL-3.0-or-later"}
PROPRIETARY = "LicenseRef-proprietary"
PROPRIETARY_FLAVOURS = {"store"}
BANNED_NATIVE = re.compile(r"exiv2|x264|x265|rubberband|libdvdcss|libdvdnav|libdvdread|postproc|smbclient|libcdio|frei0r|mutagen"
                           r"|^openssl$|^boringssl$", re.I)
GPL_FLAGS = ("--enable-gpl", "--enable-nonfree", "--enable-version3", "-Dgpl=true")
FLAVOURS = ("store", "direct", "foss", "enterprise")

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

# Licence names as written in POMs, podspecs and repository metadata → SPDX. Most specific first.
NAME_TO_SPDX: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"classpath", re.I), "GPL-2.0-only WITH Classpath-exception-2.0"),
    (re.compile(r"affero", re.I), "AGPL-3.0"),
    (re.compile(r"lesser|lgpl|library general public", re.I), "LGPL-2.1-or-later"),
    (re.compile(r"\bgpl\b|general public licen[cs]e", re.I), "GPL"),
    (re.compile(r"android software development kit|android sdk licen|google play services|play core|"
                r"developer\.android\.com/studio/terms|developers\.google\.com/terms|"
                r"google maps|google mobile services|proprietary|commercial", re.I), PROPRIETARY),
    (re.compile(r"apache", re.I), "Apache-2.0"),
    (re.compile(r"\bmit\b|expat", re.I), "MIT"),
    (re.compile(r"bsd.{0,12}(3|three|new|revised)|3-clause|eclipse distribution", re.I), "BSD-3-Clause"),
    (re.compile(r"bsd.{0,12}(2|two|simplified|freebsd)|2-clause", re.I), "BSD-2-Clause"),
    (re.compile(r"^\s*bsd\s*$|bsd licen[cs]e|bsd style|bsd-style", re.I), "BSD-3-Clause"),
    (re.compile(r"eclipse public license.{0,20}2", re.I), "EPL-2.0"),
    (re.compile(r"eclipse public license", re.I), "EPL-1.0"),
    (re.compile(r"mozilla public license.{0,20}2|mpl.?2", re.I), "MPL-2.0"),
    (re.compile(r"\bisc\b", re.I), "ISC"),
    (re.compile(r"zlib", re.I), "Zlib"),
    (re.compile(r"unicode", re.I), "Unicode-3.0"),
    (re.compile(r"boost", re.I), "BSL-1.0"),
    (re.compile(r"cc0|public domain|unlicense", re.I), "Public-Domain"),
]


def classify(text: str) -> str:
    for spdx, pat in SIGNATURES:
        if pat.search(text):
            return spdx
    return "UNKNOWN"


def spdx_from_name(name: str) -> str:
    name = name.strip()
    if name in ALLOWED or name == PROPRIETARY:
        return name
    for pat, spdx in NAME_TO_SPDX:
        if pat.search(name):
            return spdx
    return "UNKNOWN"


def _term_ok(term: str) -> bool:
    if " WITH " in term:
        base, exc = term.split(" WITH ", 1)
        return exc.strip() in ALLOWED_EXCEPTIONS or base.strip() in ALLOWED
    return term in ALLOWED


def licence_ok(spdx: str, flavour: str | None = None) -> str | None:
    """None when allowed; otherwise the reason it is not."""
    if spdx == PROPRIETARY:
        if flavour in PROPRIETARY_FLAVOURS:
            return None
        return f"proprietary licence is allowed only in the {'/'.join(sorted(PROPRIETARY_FLAVOURS))} flavour"
    # SPDX expression: every AND-term must be allowed; one allowed OR-alternative suffices.
    for term in re.split(r"\s+AND\s+", spdx.strip("() ")):
        alts = re.split(r"\s+OR\s+", term.strip("() "))
        if not any(_term_ok(a.strip("() ")) for a in alts):
            return f"licence {spdx} is not allowed"
    return None


def known_licences() -> dict[str, str]:
    """Reviewed overrides: 'group:artifact', 'pod:Name', 'spm:identity' (optionally '@version') → SPDX."""
    f = HERE / "known_licences.json"
    if not f.exists():
        return {}
    return {k: v["spdx"] if isinstance(v, dict) else v for k, v in json.loads(f.read_text(encoding="utf-8")).items()
            if not k.startswith("_")}


def lookup_known(known: dict[str, str], key: str, version: str) -> str | None:
    return known.get(f"{key}@{version}") or known.get(key)


# --- pub ----------------------------------------------------------------------------

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


# --- Gradle (Android) -------------------------------------------------------------------

GRADLE_LINE = re.compile(r"^[|\\+ -]*[+\\]--- (?!project )([^:\s]+):([^:\s]+):(\S+)(?: -> (\S+))?")


def parse_gradle_dependencies(text: str) -> set[tuple[str, str, str]]:
    """`gradle :app:dependencies --configuration X` → {(group, artifact, resolved version)}."""
    out = set()
    for line in text.splitlines():
        m = GRADLE_LINE.match(line)
        if not m:
            continue
        group, artifact, requested, resolved = m.groups()
        version = resolved or requested
        if version.startswith("{") or version in ("(*)", "(c)", "(n)"):
            continue
        out.add((group, artifact, version))
    return out


def gradle_cache() -> Path:
    return Path(os.environ.get("GRADLE_USER_HOME", Path.home() / ".gradle")) / "caches" / "modules-2" / "files-2.1"


def pom_path(group: str, artifact: str, version: str) -> Path | None:
    d = gradle_cache() / group / artifact / version
    return next(iter(sorted(d.glob(f"*/{artifact}-{version}.pom"))), None) if d.is_dir() else None


POM_NS = re.compile(r"\{.*?\}")


def pom_licences(group: str, artifact: str, version: str, depth: int = 0) -> list[str]:
    """Licence names from the POM, following <parent> POMs in the Gradle cache."""
    p = pom_path(group, artifact, version)
    if p is None or depth > 6:
        return []
    try:
        root = ET.parse(p).getroot()
    except ET.ParseError:
        return []
    for el in root.iter():
        el.tag = POM_NS.sub("", el.tag)
    names = [(lic.findtext("name") or lic.findtext("url") or "").strip() for lic in root.findall("./licenses/license")]
    names = [n for n in names if n]
    if names:
        return names
    parent = root.find("parent")
    if parent is not None:
        return pom_licences(parent.findtext("groupId") or group, parent.findtext("artifactId") or "",
                            parent.findtext("version") or "", depth + 1)
    return []


def run_gradle(flavour: str) -> str:
    android = ROOT / "app" / "android"
    gradlew = android / ("gradlew.bat" if sys.platform == "win32" else "gradlew")
    if not gradlew.exists() or not (android / "local.properties").exists():
        # Generates gradlew and local.properties without building anything.
        subprocess.run(["flutter", "build", "apk", "--config-only"], cwd=ROOT / "app", check=True,
                       shell=sys.platform == "win32")
    res = subprocess.run([str(gradlew), "-q", "--console=plain", ":app:dependencies",
                          "--configuration", f"{flavour}ReleaseRuntimeClasspath"],
                         cwd=android, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if res.returncode != 0:
        raise RuntimeError(f"gradle dependencies for {flavour} failed:\n{res.stderr[-2000:]}")
    return res.stdout


def scan_gradle(errors: list[str], inputs: dict[str, str] | None) -> list[dict]:
    known = known_licences()
    by_coord: dict[tuple[str, str, str], set[str]] = {}
    for flavour in FLAVOURS:
        try:
            text = Path(inputs[flavour]).read_text(encoding="utf-8") if inputs and flavour in inputs else run_gradle(flavour)
        except (OSError, RuntimeError, subprocess.CalledProcessError) as e:
            errors.append(f"gradle:{flavour}: cannot list dependencies ({e}); use --gradle-deps or --no-gradle")
            continue
        for coord in parse_gradle_dependencies(text):
            by_coord.setdefault(coord, set()).add(flavour)
    components = []
    for (group, artifact, version), flavours in sorted(by_coord.items()):
        key = f"{group}:{artifact}"
        spdx = lookup_known(known, key, version) or lookup_known(known, f"{group}:*", version)
        names = [] if spdx else pom_licences(group, artifact, version)
        if not spdx:
            mapped = sorted({spdx_from_name(n) for n in names})
            # Dual-licensed POMs list several licences; any allowed one is the one we take.
            allowed = [m for m in mapped if licence_ok(m, "foss") is None]
            spdx = allowed[0] if allowed else (mapped[0] if mapped else "UNKNOWN")
        for flavour in sorted(flavours):
            reason = licence_ok(spdx, flavour) if spdx != "UNKNOWN" else f"unknown licence {names or '(no POM licence)'}"
            if reason:
                errors.append(f"gradle:{key}:{version} ({flavour}): {reason}")
        components.append({"type": "library", "group": group, "name": artifact, "version": version,
                           "purl": f"pkg:maven/{group}/{artifact}@{version}",
                           "licenses": [{"expression": spdx}] if spdx != "UNKNOWN" else [],
                           "properties": [{"name": "mediahro:flavours", "value": ",".join(sorted(flavours))}]})
    return components


# --- SwiftPM and CocoaPods (Apple) -----------------------------------------------------------

def github_licence(url: str, ref: str | None) -> str | None:
    m = re.match(r"https?://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$", url)
    if not m:
        return None
    api = f"https://api.github.com/repos/{m.group(1)}/{m.group(2)}/license" + (f"?ref={ref}" if ref else "")
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "mediahro-licence-scan"}
    if os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {os.environ['GITHUB_TOKEN']}"
    try:
        with urllib.request.urlopen(urllib.request.Request(api, headers=headers), timeout=30) as r:  # noqa: S310
            spdx = (json.load(r).get("license") or {}).get("spdx_id")
    except Exception:  # noqa: BLE001 - reported as unknown by the caller
        return None
    return None if spdx in (None, "NOASSERTION") else spdx


def licence_from_dir(d: Path) -> str | None:
    for n in ("LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE", "COPYING", "License.txt"):
        if (d / n).exists():
            spdx = classify((d / n).read_text(encoding="utf-8", errors="replace"))
            return None if spdx == "UNKNOWN" else spdx
    return None


def apple_platform_dirs() -> list[Path]:
    return [ROOT / "app" / "ios", ROOT / "app" / "macos", ROOT / "packages" / "mediahro_engine" / "ios",
            ROOT / "packages" / "mediahro_engine" / "macos", ROOT / "packages" / "mediahro_engine" / "darwin"]


def parse_package_resolved(text: str) -> list[dict]:
    """Package.resolved (v1, v2, v3) → [{identity, location, version, revision, kind}]."""
    data = json.loads(text)
    pins = data.get("pins") or data.get("object", {}).get("pins", [])
    out = []
    for pin in pins:
        state = pin.get("state", {})
        location = pin.get("location") or pin.get("repositoryURL", "")
        out.append({"identity": (pin.get("identity") or pin.get("package") or Path(location).stem).lower(),
                    "location": location, "version": state.get("version") or (state.get("revision") or "")[:12],
                    "revision": state.get("revision"), "kind": pin.get("kind", "remoteSourceControl")})
    return out


def scan_swiftpm(errors: list[str], online: bool, checkouts: list[Path]) -> list[dict]:
    known = known_licences()
    components, seen = [], set()
    resolved_files = [p for d in apple_platform_dirs() if d.is_dir() for p in d.rglob("Package.resolved")]
    for f in sorted(resolved_files):
        for pin in parse_package_resolved(f.read_text(encoding="utf-8")):
            identity, location, version = pin["identity"], pin["location"], pin["version"]
            if (identity, version) in seen or pin["kind"] in ("localSourceControl", "fileSystem"):
                continue
            seen.add((identity, version))
            spdx = lookup_known(known, f"spm:{identity}", version)
            for c in checkouts:
                spdx = spdx or licence_from_dir(c / identity) or licence_from_dir(c / Path(location).stem)
            if not spdx and online:
                spdx = github_licence(location, pin["revision"])
            spdx = spdx or "UNKNOWN"
            if spdx == "UNKNOWN":
                reason = "unknown licence (add to known_licences.json or run with --online)"
            elif spdx == PROPRIETARY:
                reason = "proprietary SwiftPM package: Apple flavours are selected by dart-define, so it would ship in foss"
            else:
                reason = licence_ok(spdx, "store")
            if reason:
                errors.append(f"swiftpm:{identity}@{version} ({f.relative_to(ROOT)}): {reason}")
            purl_path = re.sub(r"^https?://", "", location).removesuffix(".git")
            components.append({"type": "library", "name": identity, "version": version,
                               "purl": f"pkg:swift/{purl_path}@{version}",
                               "licenses": [{"expression": spdx}] if spdx != "UNKNOWN" else []})
    return components


def parse_podfile_lock(text: str) -> tuple[dict[str, str], set[str]]:
    """Podfile.lock → ({pod: version}, {pods from local paths})."""
    pods: dict[str, str] = {}
    local: set[str] = set()
    section, current = None, None
    for line in text.splitlines():
        if line and not line.startswith(" "):
            section = line.rstrip(":")
            continue
        if section == "PODS":
            m = re.match(r"^  - \"?([^\s(\"]+) \(([^)]+)\)", line)
            if m:
                pods[m.group(1).split("/")[0]] = m.group(2)
        elif section == "EXTERNAL SOURCES":
            m = re.match(r"^  \"?([^\s:\"]+)\"?:$", line)
            if m:
                current = m.group(1)
            elif current and ":path:" in line:
                local.add(current)
    return pods, local


def podspec_licence(pod: str, version: str, pods_dir: Path, online: bool) -> str | None:
    spec = pods_dir / "Local Podspecs" / f"{pod}.podspec.json"
    data = json.loads(spec.read_text(encoding="utf-8")) if spec.exists() else None
    if data is None and (pods_dir / pod).is_dir():
        found = licence_from_dir(pods_dir / pod)
        if found:
            return found
    if data is None and online:
        shard = "/".join(hashlib.md5(pod.encode()).hexdigest()[:3])  # noqa: S324 - CocoaPods trunk sharding
        url = f"https://cdn.cocoapods.org/Specs/{shard}/{pod}/{version}/{pod}.podspec.json"
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "mediahro-licence-scan"}),
                                        timeout=30) as r:  # noqa: S310
                data = json.load(r)
        except Exception:  # noqa: BLE001 - reported as unknown by the caller
            data = None
    if not data:
        return None
    lic = data.get("license")
    name = lic.get("type", "") if isinstance(lic, dict) else (lic or "")
    spdx = spdx_from_name(name)
    return None if spdx == "UNKNOWN" else spdx


def scan_cocoapods(errors: list[str], online: bool) -> list[dict]:
    known = known_licences()
    components = []
    for d in apple_platform_dirs():
        lock = d / "Podfile.lock"
        if not lock.exists():
            continue
        pods, local = parse_podfile_lock(lock.read_text(encoding="utf-8"))
        for pod, version in sorted(pods.items()):
            if pod in local:
                continue  # Flutter plugins and the engine plugin: covered by the pub scan / mediahro-deps manifest.
            spdx = lookup_known(known, f"pod:{pod}", version) or podspec_licence(pod, version, d / "Pods", online) or "UNKNOWN"
            if spdx == "UNKNOWN":
                reason = "unknown licence (add to known_licences.json or run with --online)"
            elif spdx == PROPRIETARY:
                reason = "proprietary pod: Apple flavours are selected by dart-define, so it would ship in foss"
            else:
                reason = licence_ok(spdx, "store")
            if reason:
                errors.append(f"cocoapods:{pod}@{version} ({lock.relative_to(ROOT)}): {reason}")
            components.append({"type": "library", "name": pod, "version": version, "purl": f"pkg:cocoapods/{pod}@{version}",
                               "licenses": [{"expression": spdx}] if spdx != "UNKNOWN" else []})
    return components


# --- native (mediahro-deps) ---------------------------------------------------------------------

# Strings that only a GPL-only or banned build leaves in a binary.
BINARY_MARKERS: list[tuple[str, re.Pattern[bytes]]] = [
    ("FFmpeg built GPL", re.compile(rb"(?<![L])GPL version [23] or later")),
    ("FFmpeg built nonfree", re.compile(rb"nonfree and unredistributable")),
    ("configured with --enable-gpl / --enable-nonfree", re.compile(rb"--enable-(?:gpl|nonfree)\b")),
    ("mpv built with -Dgpl=true", re.compile(rb"-Dgpl=true")),
    # Encoder APIs only: FFmpeg's H.264/HEVC decoders legitimately parse "x264 - core" SEI strings.
    ("x264", re.compile(rb"x264_encoder_open|libx264\.so")),
    ("x265", re.compile(rb"x265_encoder_open|libx265\.so")),
    ("rubberband", re.compile(rb"RubberBandStretcher|librubberband")),
    ("libdvdcss", re.compile(rb"libdvdcss")),
    ("Exiv2", re.compile(rb"Exiv2::")),
    ("libpostproc", re.compile(rb"postproc_license|libpostproc")),
    ("OpenSSL / BoringSSL", re.compile(rb"OpenSSL \d+\.\d+\.\d+|BoringSSL|libssl\.so|libcrypto\.so|libssl-\d|libcrypto-\d")),
]
BINARY_SUFFIXES = (".so", ".dll", ".dylib")


def native_binaries(root: Path) -> list[Path]:
    out = []
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if p.suffix in BINARY_SUFFIXES or (p.parent.suffix == ".framework" and p.name == p.parent.stem):
            out.append(p)
    return sorted(out)


def scan_native_binaries(roots: list[Path], errors: list[str]) -> int:
    count = 0
    for root in roots:
        for b in native_binaries(root):
            count += 1
            data = b.read_bytes()
            for label, pat in BINARY_MARKERS:
                m = pat.search(data)
                if m:
                    found = m.group(0)[:60].decode(errors="replace")
                    errors.append(f"native-binary:{root.name}/{b.relative_to(root).as_posix()}: {label} ({found})")
    return count


def scan_native(manifests: list[Path], errors: list[str], require_complete: bool = False) -> list[dict]:
    """mediahro-deps manifest schema: {"target", "artefacts": [{"name", "version", "license", "linking",
    "configure", "source", "files", "compiled_into", "gpl_only_sources", ...}], "not_built": [...]}."""
    components = []
    for m in manifests:
        data = json.loads(m.read_text(encoding="utf-8"))
        target = data.get("target", m.parent.name)
        for a in data.get("artefacts", []):
            name, spdx, linking = a["name"], a["license"], a.get("linking", "dynamic")
            flags = " ".join(a.get("configure", []))
            if BANNED_NATIVE.search(name):
                errors.append(f"native:{target}:{name}: banned component (docs/09 §2)")
            if spdx.startswith(("GPL", "AGPL")):
                errors.append(f"native:{target}:{name}: {spdx} is never shipped (ADR-002)")
            elif licence_ok(spdx) is not None:
                errors.append(f"native:{target}:{name}: {licence_ok(spdx)}")
            if spdx in LGPL and linking != "dynamic":
                errors.append(f"native:{target}:{name}: LGPL must be dynamically linked, found {linking}")
            for flag in GPL_FLAGS:
                if re.search(re.escape(flag) + r"(?![\w-])", flags):
                    errors.append(f"native:{target}:{name}: configured with {flag}")
            for src in a.get("gpl_only_sources", []):
                errors.append(f"native:{target}:{name}: GPL-only source compiled in: {src}")
            props = [{"name": "mediahro:target", "value": target},
                     {"name": "mediahro:linking", "value": linking},
                     {"name": "mediahro:configure", "value": flags}]
            if a.get("compiled_into"):
                props.append({"name": "mediahro:compiled_into", "value": a["compiled_into"]})
            comp = {"type": "library", "name": name, "version": a.get("version", ""),
                    "licenses": [{"expression": spdx}], "properties": props}
            src = a.get("source") or {}
            if src.get("url"):
                comp["externalReferences"] = [{"type": "distribution", "url": src["url"]}]
            if src.get("sha256"):
                comp["hashes"] = [{"alg": "SHA-256", "content": src["sha256"]}]
            components.append(comp)
        if require_complete:
            for nb in data.get("not_built", []):
                if nb.get("by_design"):
                    continue  # decided absence (e.g. ADR-017), not a gap
                errors.append(f"native:{target}:{nb['name']}: not in the archive ({nb.get('reason', '')})")
    return components


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--deps-manifest", action="append", type=Path, default=[])
    ap.add_argument("--require-native", action="store_true", help="fail when no native manifest is supplied (M0 exit onwards)")
    ap.add_argument("--require-complete-native", action="store_true",
                    help="fail when an archive lists libraries it could not build (release gate 7)")
    ap.add_argument("--no-pub", action="store_true", help="skip the pub scan (native / Gradle / Apple only)")
    ap.add_argument("--no-gradle", action="store_true", help="skip the Gradle (Android) dependency scan")
    ap.add_argument("--gradle-deps", action="append", default=[], metavar="FLAVOR=FILE",
                    help="use saved `gradle :app:dependencies` output instead of running Gradle")
    ap.add_argument("--no-apple", action="store_true", help="skip the SwiftPM / CocoaPods scan")
    ap.add_argument("--swiftpm-checkouts", action="append", type=Path, default=[],
                    help="SwiftPM checkouts directory (DerivedData/.../SourcePackages/checkouts) for licence files")
    ap.add_argument("--online", action="store_true",
                    help="look up SwiftPM / CocoaPods licences on GitHub / the CocoaPods CDN when not known locally")
    args = ap.parse_args()
    manifests = args.deps_manifest or sorted((ROOT / ".deps-cache").glob("*/manifest.json"))
    errors: list[str] = []
    components = [] if args.no_pub else scan_pub(errors)
    if not args.no_gradle:
        inputs = dict(kv.split("=", 1) for kv in args.gradle_deps) if args.gradle_deps else None
        components += scan_gradle(errors, inputs)
    if not args.no_apple:
        components += scan_swiftpm(errors, args.online, args.swiftpm_checkouts)
        components += scan_cocoapods(errors, args.online)
    binaries = 0
    if manifests:
        components += scan_native(manifests, errors, args.require_complete_native)
        binaries = scan_native_binaries(sorted({m.parent for m in manifests}), errors)
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
    print(f"licence: {len(components)} components, {binaries} native binaries scanned, {len(errors)} errors; "
          f"SBOM at {out.relative_to(ROOT)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
