#!/usr/bin/env python3
"""
Coverage validator for the windowed-scenario gate.

Verifies that:
  1. Every tile in coverage.json with status='covered' references at least
     one scenario file that exists under tests/scenarios/.
  2. Every cover tag declared by a scenario file maps to a tile in
     coverage.json.
  3. (Soft warning) tiles with last_verified_commit older than HEAD~50
     should be re-verified — flagged as stale but does not fail.

Exit code:
  0 — all checks pass
  1 — at least one check failed
  2 — usage / IO error

Usage:
  python3 40k/tests/check_coverage.py
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
COVERAGE_JSON = REPO_ROOT / "40k" / "tests" / "coverage.json"
SCENARIOS_DIR = REPO_ROOT / "40k" / "tests" / "scenarios"
STALE_THRESHOLD_COMMITS = 50  # warn if last_verified_commit is older than HEAD~50


def main() -> int:
    if not COVERAGE_JSON.exists():
        print(f"FAIL: coverage.json missing at {COVERAGE_JSON}", file=sys.stderr)
        return 2

    with COVERAGE_JSON.open() as f:
        cov = json.load(f)

    errors: list[str] = []
    warnings: list[str] = []

    tiles = cov.get("tiles", [])
    if not tiles:
        errors.append("coverage.json has no tiles")
    tile_ids = {t["id"] for t in tiles}

    # Index every committed scenario file. Restrict to sp/ and mp/ subdirs
    # so non-scenario JSONs (agent_runs/, goldens/, etc.) don't trip the
    # scanner.
    all_scenario_files = list(SCENARIOS_DIR.glob("sp/*.json")) + \
        list(SCENARIOS_DIR.glob("mp/*.json"))
    # Skip schema doc + any underscore-prefixed (private/test) files
    scenario_files = [p for p in all_scenario_files if not p.name.startswith("_")]
    scenario_index: dict[str, dict] = {}
    for sp in scenario_files:
        try:
            with sp.open() as f:
                data = json.load(f)
        except Exception as exc:
            errors.append(f"could not parse scenario {sp}: {exc}")
            continue
        sid = data.get("id")
        if not sid:
            errors.append(f"scenario {sp} missing 'id'")
            continue
        if sid in scenario_index:
            errors.append(f"duplicate scenario id '{sid}': {scenario_index[sid]['_path']} vs {sp}")
            continue
        data["_path"] = str(sp.relative_to(REPO_ROOT))
        scenario_index[sid] = data

    # 1) Tile -> scenarios reference check
    # Supports two scenario reference forms:
    #   "<scenario_id>"            — sp/mp JSON file under tests/scenarios/
    #   "mp:<path/to/test.gd>"     — multi-peer GUT test file
    for tile in tiles:
        tid = tile["id"]
        status = tile.get("status", "")
        scenarios = tile.get("scenarios", [])
        if status == "covered":
            if not scenarios:
                errors.append(f"tile '{tid}' status=covered but has no scenarios[]")
                continue
            for sid in scenarios:
                if sid.startswith("mp:"):
                    rel = sid[3:]
                    if not (REPO_ROOT / "40k" / rel).is_file() and not (REPO_ROOT / rel).is_file():
                        errors.append(f"tile '{tid}' references multi-peer test '{sid}' but file not found")
                else:
                    if sid not in scenario_index:
                        errors.append(f"tile '{tid}' references scenario '{sid}' but no such file under tests/scenarios/")

    # 2) Scenario covers -> tile check
    for sid, sd in scenario_index.items():
        covers = sd.get("covers", [])
        if not covers:
            warnings.append(f"scenario '{sid}' ({sd['_path']}) has no 'covers' tags — won't be picked by --changed-only")
            continue
        for tag in covers:
            if tag not in tile_ids:
                errors.append(f"scenario '{sid}' ({sd['_path']}) declares cover tag '{tag}' but no matching tile in coverage.json")

    # 3) Staleness warning
    try:
        recent_commits = subprocess.check_output(
            ["git", "log", "--format=%H", "-n", str(STALE_THRESHOLD_COMMITS)],
            cwd=str(REPO_ROOT),
            text=True,
        ).strip().splitlines()
        recent_commits_short = {c[:7] for c in recent_commits}
        for tile in tiles:
            last = tile.get("last_verified_commit", "")
            if last and last[:7] not in recent_commits_short:
                # Could be either older than threshold or a non-existent SHA
                warnings.append(
                    f"tile '{tile['id']}' last_verified_commit '{last}' is "
                    f"older than HEAD~{STALE_THRESHOLD_COMMITS} or unreachable — re-verify"
                )
    except subprocess.CalledProcessError:
        warnings.append("could not query git history for staleness check")

    # Report
    print("=" * 60)
    print(f"coverage.json: {len(tiles)} tile(s)")
    print(f"scenario files: {len(scenario_index)} unique id(s)")
    print("=" * 60)

    if warnings:
        print("\nWARNINGS:")
        for w in warnings:
            print(f"  - {w}")

    if errors:
        print("\nERRORS:")
        for e in errors:
            print(f"  - {e}")
        print(f"\nFAIL: {len(errors)} error(s)")
        return 1

    print("\nOK: all coverage checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
