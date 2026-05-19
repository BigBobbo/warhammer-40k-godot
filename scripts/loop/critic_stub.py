#!/usr/bin/env python3
"""Stub critic for Phase 1 of the visual-regression loop.

Validates the I/O contract end to end:
  - results JSON is well-formed
  - per_step_screenshot paths in the results JSON resolve to real files
  - critique.json gets written at the expected path

The real critic is an Agent subagent invoked by the cloud Claude session
with critic_prompt.md as its system prompt. This stub lets us drive the
loop locally without burning agent tokens for harness validation.

Always emits an empty critique array (no findings). Exits non-zero only
if the I/O contract is broken — that means the runner produced bad
output, not that the scenario looks wrong.

Usage:
  critic_stub.py <results-json> <user-dir> <critique-json-out>

  results-json     path to ScenarioRunner's <scenario_id>.json
  user-dir         path to the Godot user:// dir (per_step_screenshot
                   paths in the results JSON are relative to this)
  critique-json-out path to write the (empty) critique array to
"""
from __future__ import annotations

import json
import os
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2

    results_path, user_dir, critique_path = sys.argv[1:]

    if not os.path.isfile(results_path):
        print(f"[critic_stub] FAIL results JSON missing: {results_path}", file=sys.stderr)
        return 2
    if not os.path.isdir(user_dir):
        print(f"[critic_stub] FAIL user dir missing: {user_dir}", file=sys.stderr)
        return 2

    with open(results_path) as f:
        results = json.load(f)

    steps = results.get("steps", [])
    if not steps:
        print(f"[critic_stub] FAIL no steps in results JSON", file=sys.stderr)
        return 2

    expected_shots = 0
    present = 0
    missing: list[str] = []
    enriched_with_input = 0

    for step in steps:
        rel = step.get("per_step_screenshot")
        if rel:
            expected_shots += 1
            full = os.path.join(user_dir, rel)
            if os.path.isfile(full) and os.path.getsize(full) > 0:
                present += 1
            else:
                missing.append(rel)
        if "step_input" in step:
            enriched_with_input += 1

    print(f"[critic_stub] scenario:    {results.get('scenario_id')}")
    print(f"[critic_stub] steps:       {len(steps)}")
    print(f"[critic_stub] step_input:  {enriched_with_input} enriched")
    print(f"[critic_stub] per-step shots: {present}/{expected_shots} resolved")

    if expected_shots == 0:
        print("[critic_stub] FAIL no per_step_screenshot fields in results "
              "JSON — did you set SCENARIO_SCREENSHOT_EVERY_STEP=1?",
              file=sys.stderr)
        return 2

    if missing:
        print(f"[critic_stub] FAIL {len(missing)} per-step screenshots missing:",
              file=sys.stderr)
        for m in missing[:10]:
            print(f"  - {m}", file=sys.stderr)
        return 2

    if enriched_with_input != len(steps):
        print(f"[critic_stub] FAIL only {enriched_with_input}/{len(steps)} "
              f"steps carry step_input — runner enrichment broken",
              file=sys.stderr)
        return 2

    with open(critique_path, "w") as f:
        json.dump([], f)
    print(f"[critic_stub] OK wrote empty critique to {critique_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
