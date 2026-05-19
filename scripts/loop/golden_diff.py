#!/usr/bin/env python3
"""Golden PHASH diff for the visual-regression loop.

For each per-step screenshot in the runner's results JSON, compare to a
golden under `40k/tests/scenarios/goldens/<scenario_id>_step_NN_<act>.png`
using a 64-bit perceptual hash and Hamming distance. Thresholds live in
`_thresholds.json` (per-scenario, with optional per-step overrides).

Modes:
  --diff   (default) compare and emit goldens_report.json. Exit 1 on drift.
  --bless  copy each per-step screenshot into the goldens dir, overwriting.
           Use only after manual sign-off — this is how new scenarios get
           their first goldens and how intentional UI changes propagate.

Inputs:
  --results PATH      path to ScenarioRunner's <scenario_id>.json
  --user-dir  PATH    Godot user:// dir (per_step_screenshot paths are
                      relative to this)
  --goldens-dir PATH  directory holding blessed PNGs (default:
                      40k/tests/scenarios/goldens)
  --thresholds PATH   path to _thresholds.json (default:
                      <goldens-dir>/_thresholds.json)
  --report PATH       where to write goldens_report.json (default:
                      <user-dir>/test_results/scenarios/goldens_report.json)

Report shape:
  {
    "scenario_id": "...",
    "mode": "diff" | "bless",
    "threshold_default": 4,
    "results": [
      {
        "step_idx": 0,
        "act": "wait_seconds",
        "screenshot": "test_results/scenarios/runner_smoke_step_00_wait_seconds.png",
        "golden":     "40k/tests/scenarios/goldens/runner_smoke_step_00_wait_seconds.png",
        "threshold": 4,
        "status": "match" | "drift" | "missing_golden" | "blessed",
        "hamming_distance": 0
      },
      ...
    ],
    "summary": {
      "match": 11, "drift": 0, "missing_golden": 0, "blessed": 0,
      "drifted_steps": []
    }
  }

Exit codes:
  0  --diff and no drift, or --bless completed
  1  --diff and at least one drift
  2  misuse / I/O error
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys


def _ensure_deps() -> None:
    """Lazy-install Pillow + imagehash if missing. These are runtime
    deps of this script alone; we don't want to force every contributor
    into a virtualenv just to run other parts of the project."""
    try:
        import PIL  # noqa: F401
        import imagehash  # noqa: F401
    except ImportError:
        print("[golden_diff] installing missing deps: Pillow imagehash",
              file=sys.stderr)
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "--quiet",
             "--user", "Pillow", "imagehash"]
        )


def _load_thresholds(path: str) -> dict:
    if not os.path.isfile(path):
        return {"default": 4, "per_scenario": {}, "per_step": {}}
    with open(path) as f:
        return json.load(f)


def _threshold_for(thresholds: dict, scenario_id: str, step_idx: int) -> int:
    key = f"{scenario_id}.{step_idx}"
    if key in thresholds.get("per_step", {}):
        return int(thresholds["per_step"][key])
    if scenario_id in thresholds.get("per_scenario", {}):
        return int(thresholds["per_scenario"][scenario_id])
    return int(thresholds.get("default", 4))


def _phash(path: str):
    from PIL import Image
    import imagehash
    with Image.open(path) as img:
        return imagehash.phash(img)


def _golden_name(scenario_id: str, step: dict) -> str:
    rel = step.get("per_step_screenshot", "")
    return os.path.basename(rel)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--results", required=True)
    p.add_argument("--user-dir", required=True)
    p.add_argument("--goldens-dir", default="40k/tests/scenarios/goldens")
    p.add_argument("--thresholds", default=None)
    p.add_argument("--report", default=None)
    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--diff", action="store_true", default=True)
    mode.add_argument("--bless", action="store_true", default=False)
    args = p.parse_args()

    _ensure_deps()

    thresholds_path = args.thresholds or os.path.join(args.goldens_dir, "_thresholds.json")
    thresholds = _load_thresholds(thresholds_path)

    if not os.path.isfile(args.results):
        print(f"[golden_diff] FAIL results JSON missing: {args.results}",
              file=sys.stderr)
        return 2

    with open(args.results) as f:
        results = json.load(f)

    scenario_id = results.get("scenario_id", "unknown")
    steps = results.get("steps", [])
    if not steps:
        print(f"[golden_diff] FAIL no steps in results JSON",
              file=sys.stderr)
        return 2

    os.makedirs(args.goldens_dir, exist_ok=True)

    report_results = []
    summary = {"match": 0, "drift": 0, "missing_golden": 0, "blessed": 0,
               "drifted_steps": []}

    for step in steps:
        rel = step.get("per_step_screenshot")
        if not rel:
            continue
        step_idx = step.get("step", -1)
        act = step.get("act", "")
        shot_abs = os.path.join(args.user_dir, rel)
        golden_name = _golden_name(scenario_id, step)
        golden_abs = os.path.join(args.goldens_dir, golden_name)
        threshold = _threshold_for(thresholds, scenario_id, step_idx)

        entry = {
            "step_idx": step_idx,
            "act": act,
            "screenshot": rel,
            "golden": os.path.relpath(golden_abs),
            "threshold": threshold,
        }

        if not os.path.isfile(shot_abs):
            print(f"[golden_diff] WARN screenshot missing: {shot_abs}",
                  file=sys.stderr)
            entry["status"] = "missing_screenshot"
            report_results.append(entry)
            continue

        if args.bless:
            shutil.copyfile(shot_abs, golden_abs)
            entry["status"] = "blessed"
            entry["hamming_distance"] = 0
            summary["blessed"] += 1
        elif not os.path.isfile(golden_abs):
            entry["status"] = "missing_golden"
            entry["hamming_distance"] = None
            summary["missing_golden"] += 1
        else:
            d = _phash(shot_abs) - _phash(golden_abs)
            entry["hamming_distance"] = int(d)
            if d <= threshold:
                entry["status"] = "match"
                summary["match"] += 1
            else:
                entry["status"] = "drift"
                summary["drift"] += 1
                summary["drifted_steps"].append(step_idx)

        report_results.append(entry)

    report = {
        "scenario_id": scenario_id,
        "mode": "bless" if args.bless else "diff",
        "threshold_default": thresholds.get("default", 4),
        "results": report_results,
        "summary": summary,
    }
    report_path = args.report or os.path.join(
        args.user_dir, "test_results/scenarios/goldens_report.json")
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2)

    print(f"[golden_diff] scenario:   {scenario_id}")
    print(f"[golden_diff] mode:       {report['mode']}")
    print(f"[golden_diff] match:      {summary['match']}")
    print(f"[golden_diff] drift:      {summary['drift']}"
          + (f"  steps={summary['drifted_steps']}" if summary["drift"] else ""))
    print(f"[golden_diff] missing:    {summary['missing_golden']}")
    print(f"[golden_diff] blessed:    {summary['blessed']}")
    print(f"[golden_diff] report:     {report_path}")

    if args.bless:
        return 0
    if summary["drift"] > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
