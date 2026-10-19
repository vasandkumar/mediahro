"""Install-size budget (docs/11 §5): ≤ 40 MB per ABI on mobile, ≤ 70 MB desktop.

Also fails on a > 5 % regression against tools/perf/baseline.json when a
baseline exists for the key (CLAUDE.md §1.5).

Usage: python tools/perf/size_budget.py {android|desktop} PATH [--key NAME]
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUDGET_MB = {"android": 40.0, "desktop": 70.0}


def size_of(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file())


def largest_abi_mb(apk: Path) -> float:
    """Approximate per-ABI install size: APK minus the native libs of all other ABIs."""
    with zipfile.ZipFile(apk) as z:
        per_abi: dict[str, int] = {}
        for i in z.infolist():
            parts = i.filename.split("/")
            if parts[0] == "lib" and len(parts) > 2:
                per_abi[parts[1]] = per_abi.get(parts[1], 0) + i.file_size
        total = sum(i.file_size for i in z.infolist())
    if not per_abi:
        return total / 2**20
    native = sum(per_abi.values())
    return max(total - native + n for n in per_abi.values()) / 2**20


def main() -> int:
    kind, target = sys.argv[1], Path(sys.argv[2])
    key = sys.argv[sys.argv.index("--key") + 1] if "--key" in sys.argv else f"{kind}:{target.name}"
    mb = largest_abi_mb(target) if kind == "android" and target.suffix == ".apk" else size_of(target) / 2**20
    budget = BUDGET_MB[kind]
    print(f"size: {key} {mb:.1f} MB (budget {budget:.0f} MB)")
    ok = mb <= budget
    baseline_file = ROOT / "tools" / "perf" / "baseline.json"
    if baseline_file.exists():
        base = json.loads(baseline_file.read_text(encoding="utf-8")).get(key)
        if base and mb > base * 1.05:
            print(f"size: regression > 5 % against baseline {base:.1f} MB", file=sys.stderr)
            ok = False
    if mb > budget:
        print(f"size: over budget by {mb - budget:.1f} MB", file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
