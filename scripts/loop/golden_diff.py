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


# Grid pHash — splits the image into ROWS×COLS tiles, hashes each
# independently, and returns the list. The 64-bit pHash applied to a
# full game screenshot was empirically too coarse to catch
# dialog-section-scale regressions (the unchanged battlefield
# dominated the low-frequency signature). Computing one pHash per
# tile means a regression in any one region produces a high
# per-tile distance even if 8/9 tiles still match.
GRID_ROWS = 3
GRID_COLS = 3


def _phash_grid(path: str, target_size: tuple = None):
    """Return a list of GRID_ROWS*GRID_COLS pHashes, one per tile.

    If target_size is provided, the image is resized to that size
    BEFORE tiling — this gives resolution parity between the current
    screenshot (1920×1080) and the blessed golden (480×270, see bless
    branch below). Without this the tile boundaries fall at different
    image content and the hashes are not comparable.
    """
    from PIL import Image
    import imagehash
    with Image.open(path) as src:
        if target_size and src.size != target_size:
            img = src.resize(target_size, Image.LANCZOS)
        else:
            img = src.copy()
        w, h = img.size
        tw = w // GRID_COLS
        th = h // GRID_ROWS
        hashes = []
        for r in range(GRID_ROWS):
            for c in range(GRID_COLS):
                left = c * tw
                top = r * th
                right = w if c == GRID_COLS - 1 else left + tw
                bottom = h if r == GRID_ROWS - 1 else top + th
                tile = img.crop((left, top, right, bottom))
                hashes.append(imagehash.phash(tile))
        return hashes


def _grid_distance(g1: list, g2: list) -> tuple:
    """Return (max_tile_distance, per_tile_distances).

    Max is the worst tile's Hamming distance — any single tile
    drifting trips the threshold. The per-tile list is recorded in
    the report for diagnostics.
    """
    per_tile = [int(a - b) for a, b in zip(g1, g2)]
    return max(per_tile), per_tile


def _golden_size(golden_abs: str) -> tuple:
    """Return the (w, h) of the golden image, for resolution parity."""
    from PIL import Image
    with Image.open(golden_abs) as img:
        return img.size


def _golden_name(scenario_id: str, step: dict) -> str:
    rel = step.get("per_step_screenshot", "")
    return os.path.basename(rel)


def _platform_id() -> str:
    """Return a short stable identifier for the current rendering platform.

    Goldens captured on Linux+xvfb (cloud runner / CI) have different
    font-hinting and rendering than goldens captured on macOS Metal or
    Windows D3D. Comparing across platforms produces drift everywhere
    that does not reflect any real regression — so goldens live in
    per-platform subdirectories of `40k/tests/scenarios/goldens/<id>/`.

    Override with GOLDENS_PLATFORM env var if the auto-detected id is
    wrong for your environment (e.g. a Linux dev running on a native
    display, not xvfb).
    """
    override = os.environ.get("GOLDENS_PLATFORM")
    if override:
        return override
    if sys.platform.startswith("linux"):
        # xvfb in the cloud runner sets DISPLAY but no real session type.
        # A local Linux dev typically has XDG_SESSION_TYPE=x11 or wayland.
        if os.environ.get("XDG_SESSION_TYPE"):
            return "linux-native"
        return "linux-xvfb"
    if sys.platform == "darwin":
        return "darwin"
    if sys.platform.startswith("win"):
        return "win32"
    return sys.platform


def _resolve_golden_path(goldens_dir: str, golden_name: str) -> tuple:
    """Resolve a golden's absolute path, with platform-specific lookup.

    Returns (resolved_path, is_platform_specific). Preference order:
      1. <goldens_dir>/<platform>/<golden_name>     (preferred new layout)
      2. <goldens_dir>/<golden_name>                (legacy / shared)

    The fallback to legacy lets repos with un-migrated goldens keep
    working until they bless on each platform.
    """
    platform_path = os.path.join(goldens_dir, _platform_id(), golden_name)
    if os.path.isfile(platform_path):
        return (platform_path, True)
    legacy_path = os.path.join(goldens_dir, golden_name)
    return (legacy_path, False)


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

    # Scenarios with intrinsically non-deterministic visuals
    # (multi-token tween settling, mid-tween dispatch sequences) opt
    # out of perceptual-hash comparison via the "skip_diff" list in
    # _thresholds.json. They still run, still take per-step
    # screenshots (for the critic agent's reading), but the diff
    # short-circuits to "skipped" status instead of producing noise.
    skip_diff = set(thresholds.get("skip_diff", []))
    if scenario_id in skip_diff and not args.bless:
        report = {
            "scenario_id": scenario_id,
            "mode": "diff",
            "threshold_default": thresholds.get("default", 4),
            "results": [
                {
                    "step_idx": s.get("step", -1),
                    "act": s.get("act", ""),
                    "screenshot": s.get("per_step_screenshot", ""),
                    "status": "skipped_diff",
                    "reason": "scenario_id is in _thresholds.json:skip_diff",
                }
                for s in steps if s.get("per_step_screenshot")
            ],
            "summary": {"match": 0, "drift": 0, "missing_golden": 0,
                        "blessed": 0, "skipped": len(steps),
                        "drifted_steps": []},
        }
        report_path = args.report or os.path.join(
            args.user_dir, "test_results/scenarios/goldens_report.json")
        with open(report_path, "w") as f:
            json.dump(report, f, indent=2)
        print(f"[golden_diff] scenario:   {scenario_id}")
        print(f"[golden_diff] mode:       diff (skipped — non-deterministic visual)")
        print(f"[golden_diff] report:     {report_path}")
        return 0

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
        if args.bless:
            # Always bless to the platform-specific directory. Legacy
            # platform-agnostic goldens are read-fallback only.
            platform_dir = os.path.join(args.goldens_dir, _platform_id())
            os.makedirs(platform_dir, exist_ok=True)
            golden_abs = os.path.join(platform_dir, golden_name)
            is_platform_specific = True
        else:
            golden_abs, is_platform_specific = _resolve_golden_path(
                args.goldens_dir, golden_name)
        threshold = _threshold_for(thresholds, scenario_id, step_idx)

        entry = {
            "step_idx": step_idx,
            "act": act,
            "screenshot": rel,
            "golden": os.path.relpath(golden_abs),
            "golden_is_platform_specific": is_platform_specific,
            "threshold": threshold,
        }

        if not os.path.isfile(shot_abs):
            print(f"[golden_diff] WARN screenshot missing: {shot_abs}",
                  file=sys.stderr)
            entry["status"] = "missing_screenshot"
            report_results.append(entry)
            continue

        if args.bless:
            # Downsample to quarter resolution and re-encode with max PNG
            # compression. PHASH (which downsamples to 32×32 internally) is
            # unaffected — empirically Hamming-distance-0 vs the full-size
            # source. The Agent reading the PNG sees less detail but still
            # plenty for the visual-regression categories the critic
            # prompt targets.
            from PIL import Image as _Image
            with _Image.open(shot_abs) as _src:
                w, h = _src.size
                _src.resize((max(1, w // 4), max(1, h // 4)),
                            _Image.LANCZOS).save(
                    golden_abs, optimize=True, compress_level=9)
            entry["status"] = "blessed"
            entry["hamming_distance"] = 0
            summary["blessed"] += 1
        elif not os.path.isfile(golden_abs):
            entry["status"] = "missing_golden"
            entry["hamming_distance"] = None
            summary["missing_golden"] += 1
        else:
            # Resolution parity: bless saves goldens at 1/4 resolution
            # (see bless branch above). Resize the current screenshot
            # down to match before hashing — otherwise the tile-grid
            # boundaries fall at different image content and tile
            # hashes are not comparable.
            target = _golden_size(golden_abs)
            cur_grid = _phash_grid(shot_abs, target_size=target)
            gold_grid = _phash_grid(golden_abs)
            max_d, per_tile = _grid_distance(cur_grid, gold_grid)
            entry["hamming_distance"] = max_d
            entry["per_tile_distances"] = per_tile
            if max_d <= threshold:
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
        "platform": _platform_id(),
        "threshold_default": thresholds.get("default", 4),
        "results": report_results,
        "summary": summary,
    }
    report_path = args.report or os.path.join(
        args.user_dir, "test_results/scenarios/goldens_report.json")
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2)

    print(f"[golden_diff] scenario:   {scenario_id}")
    print(f"[golden_diff] platform:   {_platform_id()}")
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
