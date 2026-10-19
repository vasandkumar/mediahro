"""Parse the feature table in docs/04-feature-specification.md.

Shared by `gen_status.py` (one-time bootstrap of STATUS.md) and
`check_status.py` (CI guard: every doc 04 ID is tracked in STATUS.md).
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "docs" / "04-feature-specification.md"
PLATFORMS = ("A", "I", "M", "W")

_ROW = re.compile(r"^\|\s*([A-Z0-9]+-\d{3})\s*\|(.+)\|\s*$")


@dataclass(frozen=True)
class Feature:
    fid: str
    name: str
    platforms_raw: str
    release_raw: str
    section: str

    def platform_state(self) -> dict[str, str]:
        """Map each platform to '1.0', '1.1', '1.2' or '-' (not applicable)."""
        raw = self.platforms_raw
        base_rel = _first_release(self.release_raw)
        if raw.strip() == "All":
            return {p: base_rel for p in PLATFORMS}
        state = {p: "-" for p in PLATFORMS}
        # Segments like "M W, I (iPad)", "I (M W 1.1)", "M W (A TV 1.1)".
        for outer, inner in re.findall(r"([^()]*)(?:\(([^)]*)\))?", raw):
            for p in re.findall(r"\b([AIMW])\b", outer):
                state[p] = base_rel
            if inner:
                later = re.search(r"\b1\.(\d)\b", inner)
                for p in re.findall(r"\b([AIMW])\b", inner):
                    if later:
                        if state[p] == "-":
                            state[p] = f"1.{later.group(1)}"
                    else:
                        state[p] = base_rel
        return state


def _first_release(raw: str) -> str:
    m = re.search(r"1\.\d", raw)
    return m.group(0) if m else "1.0"


def parse() -> list[Feature]:
    features: list[Feature] = []
    section = ""
    for line in SPEC.read_text(encoding="utf-8").splitlines():
        if line.startswith("## ") or line.startswith("### "):
            section = line.lstrip("# ").strip()
        m = _ROW.match(line)
        if not m:
            continue
        cells = [c.strip() for c in m.group(2).split("|")]
        # cells: feature, AC, platforms, release
        name, platforms, release = cells[0], cells[-2], cells[-1]
        features.append(Feature(m.group(1), name, platforms, release, section))
    return features
