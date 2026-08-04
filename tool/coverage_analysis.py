#!/usr/bin/env python3
"""Parse lcov.info and produce per-file and per-directory coverage gap analysis."""
import os
import sys
from collections import defaultdict

LCOV = "coverage/lcov.info"
THRESHOLD = 80

def parse_lcov(path):
    files = []
    current = None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("SF:"):
                current = {"file": line[3:], "instrumented": 0, "covered": 0}
            elif line.startswith("LF:"):
                current["instrumented"] = int(line[3:])
            elif line.startswith("LH:"):
                current["covered"] = int(line[3:])
            elif line == "end_of_record":
                if current is not None:
                    files.append(current)
                    current = None
    return files

def pct(covered, total):
    return (covered / total * 100) if total > 0 else 100.0

def main():
    files = parse_lcov(LCOV)
    # Filter to lib/ files
    lib_files = [f for f in files if f["file"].startswith("lib/")]
    total_instr = sum(f["instrumented"] for f in lib_files)
    total_cov = sum(f["covered"] for f in lib_files)

    print("=" * 78)
    print(f"OVERALL lib/ coverage: {total_cov}/{total_instr} = {pct(total_cov, total_instr):.2f}%")
    print(f"Threshold: {THRESHOLD}%  ->  {'PASS' if pct(total_cov,total_instr)>=THRESHOLD else 'FAIL'}")
    print(f"lib files with coverage data: {len(lib_files)}")
    print("=" * 78)

    # Per-file: compute coverage %, sort worst first
    rows = []
    for f in lib_files:
        p = pct(f["covered"], f["instrumented"])
        rows.append((f["file"], f["instrumented"], f["covered"], p))

    # --- Per-directory aggregation ---
    print("\n### PER-DIRECTORY COVERAGE (lib subdirs, by instrumented lines) ###\n")
    dir_stats = defaultdict(lambda: [0, 0])
    for fname, instr, cov, p in rows:
        d = os.path.dirname(fname)
        # aggregate up to top-level feature
        dir_stats[d][0] += instr
        dir_stats[d][1] += cov

    # top-level aggregation (lib/core, lib/features/<feat>, lib/shared)
    top_stats = defaultdict(lambda: [0, 0])
    for fname, instr, cov, p in rows:
        parts = fname.split("/")
        key = "/".join(parts[:3]) if len(parts) >= 3 and parts[1] == "features" else "/".join(parts[:2])
        top_stats[key][0] += instr
        top_stats[key][1] += cov

    print(f"{'Directory':<48} {'Cov%':>7} {'Cov/Lines':>12}")
    print("-" * 70)
    for d in sorted(top_stats, key=lambda k: pct(top_stats[k][1], top_stats[k][0])):
        instr, cov = top_stats[d]
        print(f"{d:<48} {pct(cov,instr):>6.1f}% {cov:>6}/{instr:<6}")

    # --- Worst-covered files (significant size) ---
    print("\n### WORST-COVERED FILES (>=20 instrumented lines, lowest first) ###\n")
    significant = [r for r in rows if r[1] >= 20]
    significant.sort(key=lambda r: r[3])
    print(f"{'File':<62} {'Cov%':>7} {'Cov/Lines':>12}")
    print("-" * 84)
    for fname, instr, cov, p in significant[:40]:
        short = fname if len(fname) <= 62 else "..." + fname[-59:]
        print(f"{short:<62} {p:>6.1f}% {cov:>6}/{instr:<6}")

    # --- Completely untested lib files (0% or not in lcov) ---
    print("\n### UNTESTED FILES (0% coverage, >=10 instrumented lines) ###\n")
    untested = [r for r in rows if r[3] == 0.0 and r[1] >= 10]
    untested.sort(key=lambda r: -r[1])
    print(f"{'File':<62} {'Lines':>7}")
    print("-" * 72)
    for fname, instr, cov, p in untested[:60]:
        short = fname if len(fname) <= 62 else "..." + fname[-59:]
        print(f"{short:<62} {instr:>7}")
    print(f"\nTotal untested (>=10 lines): {len(untested)} files, {sum(r[1] for r in untested)} lines")

    # --- lib files NOT in lcov at all (no test touches them) ---
    print("\n### LIB .dart FILES WITH NO COVERAGE RECORD AT ALL ###\n")
    lcov_files = set(f["file"] for f in files)
    all_lib = set()
    for root, _, fnames in os.walk("lib"):
        for n in fnames:
            if n.endswith(".dart"):
                all_lib.add(os.path.join(root, n))
    # count lines for missing
    missing = all_lib - lcov_files
    missing_lines = {}
    for m in missing:
        try:
            with open(m) as fh:
                # rough: non-blank, non-comment lines
                n = 0
                for ln in fh:
                    s = ln.strip()
                    if s and not s.startswith("//") and not s.startswith("*") and not s.startswith("/*"):
                        n += 1
            missing_lines[m] = n
        except Exception:
            missing_lines[m] = 0
    missing_sorted = sorted(missing, key=lambda m: -missing_lines[m])
    print(f"{'File':<62} {'~Lines':>7}")
    print("-" * 72)
    for m in missing_sorted[:60]:
        short = m if len(m) <= 62 else "..." + m[-59:]
        print(f"{short:<62} {missing_lines[m]:>7}")
    print(f"\nTotal lib files with NO coverage record: {len(missing)} (~{sum(missing_lines.values())} lines)")

if __name__ == "__main__":
    main()