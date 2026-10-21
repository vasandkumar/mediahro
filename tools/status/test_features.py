"""Tests for tools/status/features.py (run: python -m unittest discover -s tools/status)."""

from __future__ import annotations

import unittest

import features


def _feature(release: str, platforms: str = "All") -> features.Feature:
    return features.Feature("MUS-010", "Fingerprinting", platforms, release, "Music")


class RemovedReleaseTest(unittest.TestCase):
    def test_dash_cells_are_removed(self) -> None:
        for cell in ("—", "-", "–", " — ", "Removed", "Removed by owner (ADR-047)"):
            f = _feature(cell)
            self.assertTrue(f.removed, cell)
            self.assertEqual(set(f.platform_state().values()), {"-"}, cell)

    def test_versions_are_not_removed(self) -> None:
        for cell, want in (("1.0", "1.0"), ("1.1", "1.1"), ("1.2", "1.2"), ("", "1.0")):
            f = _feature(cell)
            self.assertFalse(f.removed, cell)
            self.assertEqual(f.platform_state()["A"], want, cell)

    def test_partial_platforms_keep_working(self) -> None:
        state = _feature("1.0", "I (M W 1.1)").platform_state()
        self.assertEqual(state, {"A": "-", "I": "1.0", "M": "1.1", "W": "1.1"})

    def test_spec_marks_mus_010_removed(self) -> None:
        mus = {f.fid: f for f in features.parse()}["MUS-010"]
        self.assertTrue(mus.removed)


if __name__ == "__main__":
    unittest.main()
