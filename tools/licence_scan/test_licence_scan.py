"""Tests for tools/licence_scan (run: python -m unittest discover -s tools/licence_scan)."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import licence_scan as ls

GRADLE_OUTPUT = """
fossReleaseRuntimeClasspath - Runtime classpath of '/fossRelease'.
+--- io.flutter:flutter_embedding_release:1.0.0-abc
|    +--- androidx.lifecycle:lifecycle-common:2.7.0 -> 2.8.7
|    |    \\--- org.jetbrains.kotlin:kotlin-stdlib:1.9.0 -> 2.1.0 (*)
|    \\--- androidx.annotation:annotation:{strictly 1.8.0} -> 1.8.0 (c)
+--- project :path_provider_android
|    \\--- androidx.core:core:1.13.1
\\--- org.example:gpl-thing:1.0
"""

PODFILE_LOCK = """PODS:
  - Flutter (1.0.0)
  - path_provider_foundation (0.0.1):
    - Flutter
  - Sentry/HybridSDK (8.36.0)
  - SomeLib (2.1.0)

DEPENDENCIES:
  - Flutter (from `Flutter`)

EXTERNAL SOURCES:
  Flutter:
    :path: Flutter
  path_provider_foundation:
    :path: ".symlinks/plugins/path_provider_foundation/darwin"

SPEC CHECKSUMS:
  Flutter: abc
"""


class LicenceTests(unittest.TestCase):
    def test_spdx_expressions(self):
        self.assertIsNone(ls.licence_ok("Apache-2.0 OR MIT"))
        self.assertIsNone(ls.licence_ok("BSD-3-Clause AND Apache-2.0 AND MIT AND GPL-3.0-or-later WITH Bison-exception-2.2"))
        self.assertIsNone(ls.licence_ok("GPL-2.0-only WITH Classpath-exception-2.0"))
        self.assertIsNotNone(ls.licence_ok("GPL-2.0-or-later"))
        self.assertIsNotNone(ls.licence_ok("MIT AND GPL-3.0-only"))
        self.assertIsNone(ls.licence_ok("GPL-2.0-only OR BSD-3-Clause"))

    def test_proprietary_only_in_store(self):
        self.assertIsNone(ls.licence_ok(ls.PROPRIETARY, "store"))
        for flavour in ("foss", "direct", "enterprise", None):
            self.assertIsNotNone(ls.licence_ok(ls.PROPRIETARY, flavour))

    def test_licence_names(self):
        self.assertEqual(ls.spdx_from_name("The Apache Software License, Version 2.0"), "Apache-2.0")
        self.assertEqual(ls.spdx_from_name("MIT License"), "MIT")
        self.assertEqual(ls.spdx_from_name("New BSD License"), "BSD-3-Clause")
        self.assertEqual(ls.spdx_from_name("GNU General Public License, version 2"), "GPL")
        self.assertEqual(ls.spdx_from_name("GNU General Public License, version 2 with the Classpath Exception"),
                         "GPL-2.0-only WITH Classpath-exception-2.0")
        self.assertEqual(ls.spdx_from_name("GNU Lesser General Public License"), "LGPL-2.1-or-later")
        self.assertEqual(ls.spdx_from_name("Android Software Development Kit License"), ls.PROPRIETARY)

    def test_gradle_parse(self):
        coords = ls.parse_gradle_dependencies(GRADLE_OUTPUT)
        self.assertIn(("androidx.lifecycle", "lifecycle-common", "2.8.7"), coords)
        self.assertIn(("org.jetbrains.kotlin", "kotlin-stdlib", "2.1.0"), coords)
        self.assertIn(("androidx.core", "core", "1.13.1"), coords)
        self.assertIn(("org.example", "gpl-thing", "1.0"), coords)
        self.assertFalse(any(c[1] == "path_provider_android" for c in coords))

    def test_gradle_scan_uses_poms(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / "caches" / "modules-2" / "files-2.1"

            def pom(group, artifact, version, body):
                d = cache / group / artifact / version / "h"
                d.mkdir(parents=True)
                (d / f"{artifact}-{version}.pom").write_text(
                    f'<project xmlns="http://maven.apache.org/POM/4.0.0">{body}</project>', encoding="utf-8")

            lic = lambda n: f"<licenses><license><name>{n}</name></license></licenses>"  # noqa: E731
            pom("a.b", "ok", "1", lic("Apache License, Version 2.0"))
            pom("a.b", "parent", "2", lic("MIT"))
            pom("a.b", "child", "1", "<parent><groupId>a.b</groupId><artifactId>parent</artifactId><version>2</version></parent>")
            pom("a.b", "bad", "1", lic("GNU General Public License v3"))
            pom("a.b", "cast", "1", lic("Android Software Development Kit License"))
            deps = Path(tmp) / "deps.txt"
            deps.write_text("+--- a.b:ok:1\n+--- a.b:child:1\n+--- a.b:bad:1\n\\--- a.b:cast:1\n", encoding="utf-8")
            store = Path(tmp) / "store.txt"
            store.write_text("\\--- a.b:cast:1\n", encoding="utf-8")
            import os
            old = os.environ.get("GRADLE_USER_HOME")
            os.environ["GRADLE_USER_HOME"] = tmp
            try:
                errors: list[str] = []
                comps = ls.scan_gradle(errors, {"foss": str(deps), "store": str(store), "direct": str(store),
                                                "enterprise": str(store)})
            finally:
                if old is None:
                    del os.environ["GRADLE_USER_HOME"]
                else:
                    os.environ["GRADLE_USER_HOME"] = old
            by = {c["name"]: c for c in comps}
            self.assertEqual(by["child"]["licenses"], [{"expression": "MIT"}])
            self.assertTrue(any("a.b:bad:1 (foss)" in e for e in errors))
            self.assertTrue(any("a.b:cast:1 (foss)" in e for e in errors))
            self.assertTrue(any("a.b:cast:1 (direct)" in e for e in errors))
            self.assertFalse(any("a.b:cast:1 (store)" in e for e in errors))
            self.assertFalse(any("a.b:ok:1" in e for e in errors))

    def test_podfile_lock(self):
        pods, local = ls.parse_podfile_lock(PODFILE_LOCK)
        self.assertEqual(pods["Sentry"], "8.36.0")
        self.assertEqual(pods["SomeLib"], "2.1.0")
        self.assertEqual(local, {"Flutter", "path_provider_foundation"})

    def test_package_resolved_versions(self):
        v2 = json.dumps({"pins": [{"identity": "swift-collections", "kind": "remoteSourceControl",
                                   "location": "https://github.com/apple/swift-collections.git",
                                   "state": {"revision": "abcdef1234567890", "version": "1.1.4"}}], "version": 2})
        v1 = json.dumps({"object": {"pins": [{"package": "Alamofire", "repositoryURL": "https://github.com/Alamofire/Alamofire.git",
                                              "state": {"revision": "0123456789abcdef", "version": None}}]}, "version": 1})
        self.assertEqual(ls.parse_package_resolved(v2)[0]["version"], "1.1.4")
        p1 = ls.parse_package_resolved(v1)[0]
        self.assertEqual((p1["identity"], p1["version"]), ("alamofire", "0123456789ab"))

    def _archive(self, tmp: Path, artefacts: list[dict], binary: bytes = b"") -> Path:
        d = tmp / "android-arm64-v8a"
        (d / "lib").mkdir(parents=True)
        (d / "manifest.json").write_text(json.dumps({"target": "android-arm64-v8a", "artefacts": artefacts}), encoding="utf-8")
        (d / "lib" / "libavcodec.so").write_bytes(b"\x7fELF" + binary)
        return d / "manifest.json"

    def test_native_clean(self):
        with tempfile.TemporaryDirectory() as t:
            m = self._archive(Path(t), [
                {"name": "ffmpeg", "version": "8.1.3", "license": "LGPL-2.1-or-later", "linking": "dynamic",
                 "configure": ["--enable-shared", "--extra-cflags=-D_FORTIFY_SOURCE=2"], "gpl_only_sources": []},
                {"name": "glslang", "version": "16", "license": "BSD-3-Clause AND GPL-3.0-or-later WITH Bison-exception-2.2",
                 "linking": "any", "configure": [], "gpl_only_sources": [], "gpl_with_exception_sources": ["x_tab.cpp"]},
            ], b"LGPL version 2.1 or later\0--enable-shared")
            errors: list[str] = []
            ls.scan_native([m], errors)
            ls.scan_native_binaries([m.parent], errors)
            self.assertEqual(errors, [])

    def test_native_failures(self):
        with tempfile.TemporaryDirectory() as t:
            m = self._archive(Path(t), [
                {"name": "ffmpeg", "version": "8", "license": "LGPL-2.1-or-later", "linking": "static-or-dynamic",
                 "configure": ["--enable-gpl"], "gpl_only_sources": ["libavfilter/vf_foo.c"]},
                {"name": "x264", "version": "1", "license": "MIT", "linking": "any", "configure": []},
            ], b"GPL version 2 or later\0OpenSSL 3.0.13\0x264_encoder_open_164")
            errors: list[str] = []
            ls.scan_native([m], errors)
            ls.scan_native_binaries([m.parent], errors)
            text = "\n".join(errors)
            for needle in ("LGPL must be dynamically linked", "configured with --enable-gpl", "GPL-only source compiled in",
                           "x264: banned", "FFmpeg built GPL", "OpenSSL", ": x264 ("):
                self.assertIn(needle, text)

    def test_not_built_by_design_is_not_a_gap(self):
        with tempfile.TemporaryDirectory() as t:
            m = self._archive(Path(t), [])
            data = json.loads(m.read_text(encoding="utf-8"))
            data["not_built"] = [{"name": "libssh2", "reason": "by design: ADR-017", "by_design": True},
                                 {"name": "libfoo", "reason": "build failed"}]
            m.write_text(json.dumps(data), encoding="utf-8")
            errors: list[str] = []
            ls.scan_native([m], errors, require_complete=True)
            self.assertEqual(len(errors), 1)
            self.assertIn("libfoo", errors[0])

    def test_lgpl_marker_is_not_gpl(self):
        with tempfile.TemporaryDirectory() as t:
            m = self._archive(Path(t), [], b"LGPL version 2.1 or later\0LGPL version 3 or later\0x264 - core %d")
            errors: list[str] = []
            ls.scan_native_binaries([m.parent], errors)
            self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
