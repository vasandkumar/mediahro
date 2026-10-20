"""Install-size budget (docs/11 §5): Android ≤ 75 MB per ABI (ADR-019), ≤ 70 MB desktop.

Also fails on a > 5 % regression against tools/perf/baseline.json when a
baseline exists for the key (CLAUDE.md §1.5).

Usage: python tools/perf/size_budget.py {android|desktop} PATH [--key NAME]
"""

from __future__ import annotations

import json
import os
import struct
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUDGET_MB = {"android": 75.0, "macos": 175.0, "desktop": 70.0}


def _thin_size(p: Path, arch_index: int | None) -> int:
    """File size counting only one slice of a universal (fat) Mach-O binary."""
    size = p.stat().st_size
    if size < 8:
        return size
    with p.open("rb") as f:
        magic, n = struct.unpack(">II", f.read(8))
        if magic not in (0xCAFEBABE, 0xCAFEBABF) or n > 16:
            return size
        wide = magic == 0xCAFEBABF
        slices = []
        for _ in range(n):
            if wide:
                _, _, _off, sz, _, _ = struct.unpack(">iiQQII", f.read(32))
            else:
                _, _, _off, sz, _ = struct.unpack(">iiIII", f.read(20))
            slices.append(sz)
    fat_overhead = size - sum(slices)
    return fat_overhead + (max(slices) if arch_index is None else slices[min(arch_index, len(slices) - 1)])


def size_of(path: Path, thin: bool = False) -> int:
    if path.is_file():
        return _thin_size(path, None) if thin else path.stat().st_size
    files = [p for p in path.rglob("*") if p.is_file() and not p.is_symlink()]
    return sum(_thin_size(p, None) if thin else p.stat().st_size for p in files)


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
    if not target.exists():
        print(f"size: {target} does not exist; the build artefact is missing", file=sys.stderr)
        return 1
    key = sys.argv[sys.argv.index("--key") + 1] if "--key" in sys.argv else f"{kind}:{target.name}"
    if kind == "android" and target.suffix == ".apk":
        mb = largest_abi_mb(target)
    else:
        # Desktop budget applies to the whole (universal) bundle; symlinks are not double-counted.
        mb = size_of(target) / 2**20
        thin = size_of(target, thin=True) / 2**20
        if abs(thin - mb) > 0.05:
            print(f"size: {key} largest single architecture {thin:.1f} MB (informational)")
    budget = BUDGET_MB[kind]
    print(f"size: {key} {mb:.1f} MB (budget {budget:.0f} MB)")
    ok = mb <= budget
    baseline_file = ROOT / "tools" / "perf" / "baseline.json"
    if baseline_file.exists():
        base = json.loads(baseline_file.read_text(encoding="utf-8")).get(key)
        if isinstance(base, (int, float)) and mb > base * 1.05:
            msg = (
                f"size: {key} grew > 5 % against baseline {base:.1f} MB ({mb:.1f} MB). If the growth is a doc 04"
                " feature, the orchestrator raises tools/perf/baseline.json in the merge commit (ADR-020);"
                " otherwise optimise it away."
            )
            if os.environ.get("GITHUB_EVENT_NAME") == "pull_request":
                # Lanes don't edit baseline.json (docs/lanes rule 4): report on PRs, enforce on main.
                print(f"::warning::{msg}")
                summary = os.environ.get("GITHUB_STEP_SUMMARY")
                if summary:
                    with open(summary, "a", encoding="utf-8") as fh:
                        fh.write(f"- size growth: {key} {base:.1f} → {mb:.1f} MB\n")
            else:
                print(msg, file=sys.stderr)
                ok = False
    if mb > budget:
        print(f"size: over budget by {mb - budget:.1f} MB", file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
