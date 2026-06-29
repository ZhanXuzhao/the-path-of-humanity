#!/usr/bin/env python3
"""统计项目代码行数"""

from pathlib import Path

ROOT = Path(__file__).parent

# 要统计的文件扩展名
EXTENSIONS = {
    ".gd": "GDScript",
    ".tscn": "Scene",
}

def count_lines(path: Path) -> int:
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return sum(1 for _ in f)
    except Exception:
        return 0

def main():
    results: dict[str, list[tuple[Path, int]]] = {v: [] for v in EXTENSIONS.values()}
    total_lines = 0

    for f in sorted(ROOT.rglob("*")):
        if f.suffix in EXTENSIONS:
            cat = EXTENSIONS[f.suffix]
            lines = count_lines(f)
            results[cat].append((f.relative_to(ROOT), lines))
            total_lines += lines

    print(f"{'='*60}")
    print(f"  代码统计 — The Path of Humanity")
    print(f"{'='*60}")
    print()
    for cat, files in results.items():
        if not files:
            continue
        print(f"  [{cat}]")
        cat_total = sum(l for _, l in files)
        for p, l in files:
            print(f"    {l:>6}  {p}")
        print(f"    {'─'*40}")
        print(f"    {cat_total:>6}  小计")
        print()

    print(f"{'─'*60}")
    print(f"  {total_lines:>6}  总计")
    print(f"{'='*60}")

if __name__ == "__main__":
    main()
