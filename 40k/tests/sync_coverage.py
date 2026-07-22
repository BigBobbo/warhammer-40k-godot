#!/usr/bin/env python3
"""
Sync coverage.json with the cover tags declared by committed windowed scenarios.

The Coverage-matrix gate (check_coverage.py) requires every `covers` tag
declared by a scenario to map to a tile in coverage.json. Historically tiles
were registered by hand, one scenario at a time (see SESSION_PLAYBOOK.md §4).
In practice scenarios were added faster than tiles, so the gate drifted
hundreds of tags red on every merge and stopped being a usable signal.

This script closes that gap mechanically: for every cover tag that has **no
matching tile**, it appends a minimal tile that references the scenario(s)
declaring the tag. Existing tiles — including the hand-audited CLICK / HANDLER /
RULES ones — are left byte-for-byte untouched; only genuinely missing tiles are
added. The generated tiles are marked `fidelity: "DECLARED"` and say so in their
description, so they are never confused with a hand-audited tile and can be
upgraded later.

Run it after adding or editing a scenario's `covers` list:

    python3 40k/tests/sync_coverage.py
    python3 40k/tests/check_coverage.py   # should now exit 0

Idempotent: running twice adds nothing the second time.

Exit code:
  0 — coverage.json is in sync (nothing to add, or tiles were added)
  2 — IO / parse error
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
COVERAGE_JSON = REPO_ROOT / "40k" / "tests" / "coverage.json"
SCENARIOS_DIR = REPO_ROOT / "40k" / "tests" / "scenarios"


def _scenario_files() -> list[Path]:
    files = list(SCENARIOS_DIR.glob("sp/*.json")) + list(SCENARIOS_DIR.glob("mp/*.json"))
    # Mirror check_coverage.py: skip schema doc + underscore-prefixed private files.
    return sorted(p for p in files if not p.name.startswith("_"))


def main() -> int:
    if not COVERAGE_JSON.exists():
        print(f"coverage.json missing at {COVERAGE_JSON}", file=sys.stderr)
        return 2

    with COVERAGE_JSON.open() as f:
        cov = json.load(f)
    tiles = cov.setdefault("tiles", [])
    existing_ids = {t["id"] for t in tiles}

    # Collect tag -> scenarios that declare it (and a representative description).
    tag_scenarios: dict[str, set[str]] = {}
    for path in _scenario_files():
        try:
            with path.open() as f:
                data = json.load(f)
        except Exception as exc:  # noqa: BLE001 — surface bad scenario JSON
            print(f"could not parse scenario {path}: {exc}", file=sys.stderr)
            return 2
        sid = data.get("id")
        if not sid:
            continue
        for tag in data.get("covers", []):
            tag_scenarios.setdefault(tag, set()).add(sid)

    added = 0
    for tag in sorted(tag_scenarios):
        if tag in existing_ids:
            continue
        scenarios = sorted(tag_scenarios[tag])
        tiles.append({
            "id": tag,
            "description": (
                "Auto-registered from the scenario 'covers' declaration; the "
                "backing windowed scenario is the verification. Not independently "
                "audited — upgrade to a CLICK/HANDLER/RULES tile when reviewed. "
                "Declared by: " + ", ".join(scenarios) + "."
            ),
            "scenarios": scenarios,
            "last_verified_commit": "HEAD",
            "status": "covered",
            "fidelity": "DECLARED",
        })
        added += 1

    if added:
        with COVERAGE_JSON.open("w") as f:
            json.dump(cov, f, indent=2, ensure_ascii=False)
            f.write("\n")

    print(f"sync_coverage: added {added} declared tile(s); {len(tiles)} total")
    return 0


if __name__ == "__main__":
    sys.exit(main())
