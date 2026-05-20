#!/usr/bin/env python3
"""Add a final 'screenshot' step to every visual scenario that doesn't
already produce one, so the Tier B review HTML has an image per task.

For tasks where the feature renders inside the board (tokens, rings,
overlays), prepend a `fit_view_to_board()` execute_script so the
default-zoom camera doesn't crop everything.

Idempotent — already-modified scenarios are left alone.
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENARIO_DIR = ROOT / "tests" / "scenarios" / "visual"

# Tasks whose feature is on the board and needs fit_view_to_board first.
# (Tasks whose feature is HUD-only — panels, top-bar — don't need it.)
NEEDS_FIT = {
    "T08", "T09", "T10", "T11", "T15", "T16", "T17", "T18", "T19",
    "T28", "T29", "T30", "T32", "T34",
}

# Tasks where a "review" screenshot adds no information (pure code
# audits — constant lookups, no visual surface, no fixture context).
# Tasks with a visual surface but unfinished rendering (T03, T05, T33,
# T36, T40) are NOT in this set — they get a fixture-context screenshot
# so the reviewer sees the scene where the feature WOULD render, and
# a known-gap warning explains the missing rendering.
SKIP = {
    "T12",  # constant-only audit (UIConstants references)
    "T41",  # constant-only audit (faction vs slot)
    "T42",  # constant-only helper (striped_pattern return value)
    "T43",  # constant-only (primary_cta_color)
    "T44",  # constant-only (motion budget constants)
}


def patch(path: Path) -> tuple[bool, str]:
    """Return (modified, status)."""
    task_id = path.name.split("_")[0]
    if task_id in SKIP:
        return False, "skip (pure-property test)"

    with path.open() as f:
        data = json.load(f)
    steps: list = data.get("steps", [])
    # Already has a screenshot labelled "*_review"?
    for s in steps:
        if isinstance(s, dict) and s.get("act") == "screenshot":
            lbl = str(s.get("label", ""))
            if lbl.endswith("_review"):
                return False, "already has _review screenshot"

    # Find the expect_baseline_unchanged step (always last in our scenarios)
    insert_at = len(steps)
    for i, s in enumerate(steps):
        if isinstance(s, dict) and s.get("act") == "expect_baseline_unchanged":
            insert_at = i
            break

    new_steps: list = []
    if task_id in NEEDS_FIT:
        new_steps.append({
            "act": "execute_script",
            "script": "main.fit_view_to_board()",
        })
    new_steps.append({
        "act": "wait_frames",
        "frames": 3,
    })
    new_steps.append({
        "act": "screenshot",
        "label": f"{task_id}_review",
    })

    steps[insert_at:insert_at] = new_steps
    data["steps"] = steps

    with path.open("w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    return True, "added _review screenshot"


def main() -> int:
    count_mod = 0
    count_skip = 0
    for p in sorted(SCENARIO_DIR.glob("T*_*.json")):
        modified, status = patch(p)
        print(f"  {p.name:40s} {status}")
        if modified:
            count_mod += 1
        else:
            count_skip += 1
    print(f"Modified {count_mod}, untouched {count_skip}.")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
