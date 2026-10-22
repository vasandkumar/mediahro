"""Tests for gen_native_notices.py (CORE-013). Run: python -m unittest tools/licences/test_gen_native_notices.py"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_native_notices as g  # noqa: E402


def make_cache(root: Path, target: str, artefacts: list[dict], texts: dict[str, str]) -> None:
    base = root / target
    (base / "licenses").mkdir(parents=True)
    (base / "manifest.json").write_text(
        json.dumps({"target": target, "artefacts": artefacts}), encoding="utf-8"
    )
    for name, text in texts.items():
        (base / "licenses" / f"{name}.txt").write_text(text, encoding="utf-8")


def art(name: str, licence: str = "MIT", **extra) -> dict:
    return {
        "name": name,
        "version": "1.0",
        "license": licence,
        "linking": "dynamic",
        "source": {"url": f"https://example.org/{name}.tar.xz", "sha256": "ab" * 32},
        "configure": ["--enable-shared"],
        **extra,
    }


class GenTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.lock = self.root / "deps.lock"
        self.lock.write_text(
            json.dumps(
                {
                    "repository": "o/mediahro-deps",
                    "release": "v1",
                    "sources": {"url": "https://example.org/sources.tar", "sha256": "cd" * 32},
                }
            ),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def build(self, targets: list[str]) -> dict:
        return g.build(targets, cache=self.root, lock_path=self.lock)

    def test_release_and_sources_come_from_the_lock(self) -> None:
        make_cache(self.root, "android-arm64-v8a", [art("zlib")], {"zlib": "text"})
        doc = self.build(["android-arm64-v8a"])
        self.assertEqual(doc["release"], "v1")
        self.assertEqual(doc["releaseUrl"], "https://github.com/o/mediahro-deps/releases/tag/v1")
        self.assertEqual(doc["sources"]["url"], "https://example.org/sources.tar")

    def test_configure_is_kept_only_for_the_libraries_that_need_it(self) -> None:
        make_cache(
            self.root,
            "android-arm64-v8a",
            [art("ffmpeg", "LGPL-2.1-or-later"), art("zlib")],
            {"ffmpeg": "lgpl", "zlib": "zlib"},
        )
        by = {c["name"]: c for c in self.build(["android-arm64-v8a"])["components"]}
        self.assertEqual(by["ffmpeg"]["configure"], ["--enable-shared"])
        self.assertNotIn("configure", by["zlib"])

    def test_identical_texts_are_stored_once(self) -> None:
        make_cache(
            self.root,
            "android-arm64-v8a",
            [art("a"), art("b"), art("c")],
            {"a": "same", "b": "same", "c": "other"},
        )
        doc = self.build(["android-arm64-v8a"])
        self.assertEqual(len(doc["texts"]), 2)
        ids = {c["name"]: c["textId"] for c in doc["components"]}
        self.assertEqual(ids["a"], ids["b"])
        self.assertNotEqual(ids["a"], ids["c"])
        self.assertEqual(doc["texts"][ids["a"]], "same")

    def test_targets_are_merged_by_platform(self) -> None:
        make_cache(self.root, "android-arm64-v8a", [art("zlib")], {"zlib": "t"})
        make_cache(self.root, "android-x86_64", [art("zlib"), art("extra")], {"zlib": "t", "extra": "t"})
        doc = self.build(["android-arm64-v8a", "android-x86_64"])
        by = {c["name"]: c for c in doc["components"]}
        self.assertEqual(by["zlib"]["platforms"], ["android"])
        self.assertEqual(len(doc["components"]), 2)

    def test_a_gpl_only_or_agpl_library_is_refused(self) -> None:
        for licence in ("AGPL-3.0-or-later", "GPL-3.0-only"):
            with self.subTest(licence):
                make_cache(self.root, "android-arm64-v8a", [art("bad", licence)], {"bad": "t"})
                with self.assertRaises(SystemExit):
                    self.build(["android-arm64-v8a"])
                import shutil

                shutil.rmtree(self.root / "android-arm64-v8a")

    def test_a_library_without_a_licence_text_is_refused(self) -> None:
        make_cache(self.root, "android-arm64-v8a", [art("zlib")], {})
        with self.assertRaises(SystemExit):
            self.build(["android-arm64-v8a"])

    def test_check_reports_a_stale_file(self) -> None:
        make_cache(self.root, "android-arm64-v8a", [art("zlib")], {"zlib": "t"})
        out = self.root / "native.json"
        doc = self.build(["android-arm64-v8a"])
        out.write_text(g.render(doc), encoding="utf-8")
        old_cache, old_lock = g.CACHE, g.LOCK
        g.CACHE, g.LOCK = self.root, self.lock
        try:
            args = ["--target", "android-arm64-v8a", "--out", str(out), "--check"]
            self.assertEqual(g.main(args), 0)
            out.write_text(g.render({**doc, "release": "v0"}), encoding="utf-8")
            self.assertEqual(g.main(args), 1)
        finally:
            g.CACHE, g.LOCK = old_cache, old_lock

    def test_the_committed_asset_is_for_the_pinned_release(self) -> None:
        asset = g.OUT
        if not asset.exists():
            self.skipTest("asset not generated")
        doc = json.loads(asset.read_text(encoding="utf-8"))
        lock = json.loads(g.LOCK.read_text(encoding="utf-8"))
        self.assertEqual(doc["release"], lock["release"])


if __name__ == "__main__":
    unittest.main()
