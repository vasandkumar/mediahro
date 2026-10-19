"""CI guard: every feature ID in docs/04 appears exactly once in STATUS.md,
and no 1.0 platform cell has been silently changed to "—" (scope narrowing).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import features  # noqa: E402

STATUS = features.ROOT / "STATUS.md"


def main() -> int:
    text = STATUS.read_text(encoding="utf-8")
    rows = {}
    for line in text.splitlines():
        m = re.match(r"^\|\s*([A-Z0-9]+-\d{3})\s*\|", line)
        if m:
            if m.group(1) in rows:
                print(f"duplicate row for {m.group(1)}")
                return 1
            rows[m.group(1)] = [c.strip() for c in line.strip().strip("|").split("|")]
    errors = []
    for f in features.parse():
        row = rows.get(f.fid)
        if row is None:
            errors.append(f"{f.fid} missing from STATUS.md")
            continue
        cells = dict(zip(features.PLATFORMS, row[3:7]))
        for p, want in f.platform_state().items():
            have = cells.get(p, "")
            if want == "1.0" and have not in ("☐", "☑", "⛔"):
                errors.append(f"{f.fid} platform {p}: expected ☐/☑/⛔ for a 1.0 platform, found '{have}'")
    for e in errors:
        print(e)
    ticked = sum(r[3:7].count("☑") for r in rows.values())
    total = sum(r[3:7].count("☐") + r[3:7].count("☑") + r[3:7].count("⛔") for r in rows.values())
    print(f"{len(rows)} IDs tracked; {ticked}/{total} platform cells done")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
