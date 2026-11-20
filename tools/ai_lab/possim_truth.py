#!/usr/bin/env python3
"""Ground truth for AIPositionSim: what really happened after each saved position.

For every measured movement case (r4_designs/measured_positions.json) play the
AI's own line once from the save to the rollout horizon with --bench-trace: at
the end of every player turn the runner records who controls each objective
and every unit's centre and share of wounds left. forecast_prefilter.py
--truth compares AIPositionSim's base-line prediction with these (ownership
Brier score, units lost, where the unit went) — a calibration target that is
independent of the rollout effect E the predictor is finally judged on.

Usage:
    python3 tools/ai_lab/possim_truth.py --out DIR [--lanes 3] [--limit N] [--seed 9001]
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rollout  # noqa: E402
from forecast_prefilter import jobs_from_measured  # noqa: E402
from run_lanes import userdata_dir  # noqa: E402


def one(job: dict, seed: int, ud: str, out_dir: str, max_seconds: float) -> dict:
    dst = os.path.join(out_dir, job["job"] + ".json")
    if os.path.exists(dst):
        return {"job": job["job"], "status": "cached"}
    case = rollout.load_case(os.path.join(rollout.REPO, job["case"]))
    fixture = rollout.install_fixture(case, ud)
    out_rel = "test_results/possim_truth/%s.json" % job["job"]
    os.makedirs(os.path.dirname(os.path.join(ud, out_rel)), exist_ok=True)
    cmd = rollout.godot_cmd() + ["--headless", "--quiet", "--path", rollout.PROJECT, "--", "--ai-benchmark",
                                 "--bench-fixture=%s" % fixture, "--bench-seed=%d" % seed, "--bench-time-scale=6",
                                 "--bench-max-seconds=%g" % max_seconds, "--bench-out=%s" % out_rel,
                                 "--bench-arm=ROLLOUT_A", "--bench-trace",
                                 "--bench-stop-round=%d" % (int(case.get("round", 1)) + 1)]
    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=max_seconds + 180)
    except subprocess.TimeoutExpired:
        return {"job": job["job"], "status": "hard_timeout"}
    src = os.path.join(ud, out_rel)
    if not os.path.exists(src):
        return {"job": job["job"], "status": "missing"}
    res = json.load(open(src))
    keep = {k: res.get(k) for k in ("status", "vp", "vp_start", "start_round", "battle_round", "trace", "seed")}
    keep["job"] = job["job"]
    keep["player"] = int(case.get("player", 1))
    json.dump(keep, open(dst, "w"))
    rec = src.replace(".json", ".record.json")
    for f in (src, rec):
        if os.path.exists(f):
            os.remove(f)
    return {"job": job["job"], "status": res.get("status"), "turns": len(res.get("trace") or [])}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True)
    ap.add_argument("--lanes", type=int, default=3)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--seed", type=int, default=9001)
    ap.add_argument("--max-seconds", type=float, default=1500)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    ud = userdata_dir()
    jobs = jobs_from_measured(a.limit)
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.lanes) as pool:
        for r in pool.map(lambda j: one(j, a.seed, ud, a.out, a.max_seconds), jobs):
            print(json.dumps(r), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
