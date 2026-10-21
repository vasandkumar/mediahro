"""Bootstrap STATUS.md from docs/04. Refuses to overwrite an existing file.

Usage: python tools/status/gen_status.py [--force]
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import features  # noqa: E402

OUT = features.ROOT / "STATUS.md"


def lane_for(fid: str) -> str:
    prefix, num = fid.split("-")
    n = int(num)
    if prefix == "CORE":
        return {
            3: "C4", 4: "C4", 5: "B2", 10: "C4", 11: "B1", 12: "C5", 13: "C5", 14: "B2",
        }.get(n, "B3")
    if prefix in ("LIB", "FILE"):
        return "B2"
    if prefix == "VID":
        return "B1" if n <= 35 else "C1"
    if prefix == "SUB":
        return "B1 → C1" if n <= 16 else "C1"
    if prefix == "AUD":
        return "C2" if n == 46 else "B1"
    if prefix in ("MUS", "POD"):
        return "C2"
    if prefix == "IMG":
        return "C3"
    if prefix == "NET":
        return "C4" if 10 <= n <= 17 else "B2"
    if prefix == "CAST":
        return "B1" if n == 5 else "C4"
    if prefix == "SYS":
        return "C4"
    if prefix == "PRIV":
        return "C3" if n == 7 else "C5"
    if prefix in ("SUP", "B2B"):
        return "C5"
    raise ValueError(fid)


def cell(state: str) -> str:
    return {"1.0": "☐", "-": "—"}.get(state, state)


def main() -> None:
    if OUT.exists() and "--force" not in sys.argv:
        sys.exit("STATUS.md exists; it is hand-maintained. Use --force to regenerate (loses ticks).")
    rows: list[str] = []
    section = None
    for f in features.parse():
        if f.section != section:
            section = f.section
            rows.append(f"\n### {section}\n")
            rows.append("| ID | Feature | Lane | A | I | M | W | Notes |")
            rows.append("|---|---|---|:-:|:-:|:-:|:-:|---|")
        st = f.platform_state()
        notes = "" if f.release_raw == "1.0" else f"Rel. {f.release_raw}"
        if f.removed:
            notes = "Removed from 1.0 by owner decision."
        rows.append(
            f"| {f.fid} | {f.name} | {lane_for(f.fid)} | "
            + " | ".join(cell(st[p]) for p in features.PLATFORMS)
            + f" | {notes} |"
        )
    template = (Path(__file__).parent / "STATUS.template.md").read_text(encoding="utf-8")
    OUT.write_text(template.replace("{{FEATURES}}", "\n".join(rows).strip()), encoding="utf-8")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
