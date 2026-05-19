#!/usr/bin/env python3
"""Order scenarios for the visual-regression loop's parallel kickoff.

Scenarios with the OLDEST `last_verified_commit` in coverage.json go
first — the longer it's been since the last green windowed run, the
more likely the player-facing UI for that feature has drifted. Tiles
without a verified commit (or scenarios on disk that don't appear in
coverage.json at all) jump to the top.

Output is the priority order one cloud Claude session should be spawned
against per row. See kickoff_parallel.md for the operator runbook.

Usage:
  python3 scripts/loop/list_scenarios_by_priority.py            # table
  python3 scripts/loop/list_scenarios_by_priority.py --tsv      # machine
  python3 scripts/loop/list_scenarios_by_priority.py --top 5    # top N
  python3 scripts/loop/list_scenarios_by_priority.py --ids      # IDs only
  python3 scripts/loop/list_scenarios_by_priority.py --paths    # paths only
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from typing import Optional

COVERAGE = "40k/tests/coverage.json"
SP_DIR = "40k/tests/scenarios/sp"
MP_DIR = "40k/tests/scenarios/mp"


def _commit_timestamp(sha: str) -> Optional[int]:
    if not sha:
        return None
    try:
        out = subprocess.check_output(
            ["git", "show", "-s", "--format=%ct", sha],
            stderr=subprocess.DEVNULL, text=True
        ).strip()
        return int(out) if out else None
    except subprocess.CalledProcessError:
        return None


def _short_sha(sha: str) -> str:
    return (sha or "")[:7]


def _find_scenario_path(scenario_id: str) -> Optional[str]:
    for d in (SP_DIR, MP_DIR):
        p = os.path.join(d, f"{scenario_id}.json")
        if os.path.isfile(p):
            return p
    return None


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--tsv", action="store_true")
    p.add_argument("--ids", action="store_true")
    p.add_argument("--paths", action="store_true")
    p.add_argument("--top", type=int, default=None)
    args = p.parse_args()

    if not os.path.isfile(COVERAGE):
        print(f"ERROR no {COVERAGE}", file=sys.stderr)
        return 2

    with open(COVERAGE) as f:
        coverage = json.load(f)

    # Per-scenario oldest commit across all tiles that reference it.
    # null/missing commit short-circuits to "highest priority".
    scenario_commit: dict[str, Optional[str]] = {}
    for tile in coverage.get("tiles", []):
        sha = tile.get("last_verified_commit") or None
        for sid in tile.get("scenarios", []):
            cur = scenario_commit.get(sid, "__unset__")
            if cur == "__unset__":
                scenario_commit[sid] = sha
            elif sha is None or cur is None:
                scenario_commit[sid] = None  # any missing → top priority
            else:
                ts_cur = _commit_timestamp(cur) or 0
                ts_new = _commit_timestamp(sha) or 0
                if ts_new < ts_cur:
                    scenario_commit[sid] = sha

    # Add disk scenarios not in coverage at all (orphans → top priority).
    on_disk_ids = set()
    for d in (SP_DIR, MP_DIR):
        if os.path.isdir(d):
            for f in os.listdir(d):
                if f.endswith(".json") and not f.startswith("_"):
                    on_disk_ids.add(f[:-5])
    for sid in on_disk_ids - set(scenario_commit):
        scenario_commit[sid] = None

    # Build rows, dropping scenarios whose file no longer exists.
    rows = []
    for sid, sha in scenario_commit.items():
        path = _find_scenario_path(sid)
        if path is None:
            continue
        ts = _commit_timestamp(sha) if sha else 0
        rows.append({
            "scenario_id": sid,
            "commit_sha": sha or "",
            "commit_ts": ts or 0,
            "scenario_path": path,
        })

    # Sort: oldest timestamp first (0 = no/unknown commit, sorts first);
    # ties broken alphabetically for determinism.
    rows.sort(key=lambda r: (r["commit_ts"], r["scenario_id"]))

    if args.top:
        rows = rows[:args.top]

    if args.ids:
        for r in rows:
            print(r["scenario_id"])
        return 0
    if args.paths:
        for r in rows:
            print(r["scenario_path"])
        return 0
    if args.tsv:
        print("priority\tcommit_ts\tcommit_sha\tscenario_id\tscenario_path")
        for i, r in enumerate(rows, 1):
            print(f"{i}\t{r['commit_ts']}\t{_short_sha(r['commit_sha'])}\t{r['scenario_id']}\t{r['scenario_path']}")
        return 0

    # Default: human table
    print(f"{'#':>3} {'commit':<10} {'age':<8} {'scenario_id':<48} scenario_path")
    print("-" * 130)
    import time
    now = int(time.time())
    for i, r in enumerate(rows, 1):
        if r["commit_ts"]:
            age_s = now - r["commit_ts"]
            age = f"{age_s // 86400}d" if age_s >= 86400 else f"{age_s // 3600}h"
        elif r["commit_sha"]:
            age = "?"  # SHA recorded but not in this clone
        else:
            age = "NEVER"
        print(f"{i:>3} {_short_sha(r['commit_sha']):<10} {age:<8} {r['scenario_id']:<48} {r['scenario_path']}")
    return 0


def _suppress_broken_pipe():
    # Common when piping --tsv output to `head`. The default SIGPIPE handler
    # turns into a Python BrokenPipeError after the consumer closes; mute it.
    try:
        sys.stdout.flush()
    except BrokenPipeError:
        pass
    try:
        sys.stdout.close()
    except Exception:
        pass


if __name__ == "__main__":
    try:
        exit_code = main()
    except BrokenPipeError:
        exit_code = 0
    _suppress_broken_pipe()
    sys.exit(exit_code)
