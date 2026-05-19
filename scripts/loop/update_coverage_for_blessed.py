#!/usr/bin/env python3
"""Refresh coverage.json's last_verified_commit for scenarios that have
fresh goldens in 40k/tests/scenarios/goldens/.

The visual-regression loop blesses goldens against a specific commit;
this script reconciles that into coverage.json so the priority script
stops re-prioritizing those scenarios as stale.

Usage:
  python3 scripts/loop/update_coverage_for_blessed.py [--dry-run] [--sha SHA]

Default SHA is HEAD. --dry-run prints the diff without writing.

For each scenario_id that has at least one golden file matching
<scenario_id>_step_NN_<act>.png, the script walks coverage.json's
tiles, and for every tile whose `scenarios` array contains that id,
sets `last_verified_commit` to the target SHA.

Scenarios with goldens but no covering tile in coverage.json are
reported separately — those need a human to add a tile (the loop
can't synthesize a feature description).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

COVERAGE = "40k/tests/coverage.json"
GOLDENS_DIR = "40k/tests/scenarios/goldens"


def _scenario_ids_with_goldens() -> set[str]:
    if not os.path.isdir(GOLDENS_DIR):
        return set()
    ids: set[str] = set()
    for f in os.listdir(GOLDENS_DIR):
        if not f.endswith(".png"):
            continue
        # Format: <scenario_id>_step_NN_<act>.png
        idx = f.find("_step_")
        if idx > 0:
            ids.add(f[:idx])
    return ids


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--sha", default=None,
                   help="target commit SHA (default: HEAD short)")
    args = p.parse_args()

    sha = args.sha or subprocess.check_output(
        ["git", "rev-parse", "--short", "HEAD"], text=True).strip()

    with open(COVERAGE) as f:
        coverage = json.load(f)

    blessed_ids = _scenario_ids_with_goldens()
    if not blessed_ids:
        print("[update_coverage] no goldens found — nothing to do")
        return 0

    print(f"[update_coverage] target SHA:   {sha}")
    print(f"[update_coverage] blessed ids:  {len(blessed_ids)}")

    updated_tiles = 0
    untouched_tiles = 0
    blessed_ids_seen_in_tiles: set[str] = set()
    for tile in coverage.get("tiles", []):
        scenarios = tile.get("scenarios", [])
        tile_match = blessed_ids.intersection(scenarios)
        if not tile_match:
            untouched_tiles += 1
            continue
        blessed_ids_seen_in_tiles.update(tile_match)
        prev = tile.get("last_verified_commit", "")
        if prev != sha:
            tile["last_verified_commit"] = sha
            updated_tiles += 1
            print(f"  {tile['id']}: {prev or '(none)'} → {sha}  (scenarios: {sorted(tile_match)})")

    orphans = sorted(blessed_ids - blessed_ids_seen_in_tiles)
    if orphans:
        print(f"")
        print(f"[update_coverage] {len(orphans)} blessed scenario(s) have no covering tile:")
        for o in orphans:
            print(f"  {o}")
        print(f"  → consider adding tiles for these in coverage.json")

    print("")
    print(f"[update_coverage] tiles updated:    {updated_tiles}")
    print(f"[update_coverage] tiles untouched:  {untouched_tiles}")

    if args.dry_run:
        print("[update_coverage] --dry-run, not writing")
        return 0

    if updated_tiles == 0:
        print("[update_coverage] nothing to write")
        return 0

    with open(COVERAGE, "w") as f:
        json.dump(coverage, f, indent=2)
    print(f"[update_coverage] wrote {COVERAGE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
