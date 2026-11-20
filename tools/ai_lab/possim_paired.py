#!/usr/bin/env python3
"""Does AIPositionSim predict what a forced move really changes?

possim_truth.py plays each measured case twice with TODAY's AI and one seed:
the AI's own line (--out A) and the measured alternative forced once
(--alt --out B). The pair differs only by that move, so the real change in
who controls each objective at each turn end (B minus A) is what a
position-aware predictor has to get right — and unlike the rollout effect E
(measured weeks ago on an older AI) it is consistent with the plan the sim
is given. This compares that real change with the sim's (alternative minus
the rebuilt plan), from a possim_replay.gd --arms=1 output.

Usage:
  python3 tools/ai_lab/possim_paired.py --cache DIR --a DIR --b DIR [--opts '{}'] [--trials 300]
"""
from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from forecast_prefilter import boot_ci, corr, spearman  # noqa: E402
from possim_sweep import truth_ends  # noqa: E402


def run_replay(cache: str, opts: dict, trials: int) -> list[dict]:
    tmp = tempfile.mkdtemp(prefix="possim_paired_")
    jobs = sorted(f[:-4] for f in os.listdir(cache) if f.endswith(".var"))
    json.dump(jobs, open(os.path.join(tmp, "j.json"), "w"))
    json.dump([{"name": "v", "opts": opts}], open(os.path.join(tmp, "v.json"), "w"))
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/bin") + ":" + env.get("PATH", "")
    out = os.path.join(tmp, "o.jsonl")
    subprocess.run(["godot", "--headless", "--path", os.path.join(REPO, "40k"), "-s", "tests/possim_replay.gd", "--",
                    "--cache=" + os.path.abspath(cache), "--jobs=" + os.path.join(tmp, "j.json"),
                    "--variants=" + os.path.join(tmp, "v.json"), "--out=" + out, "--trials=%d" % trials,
                    "--trace=1", "--arms=1"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
    return [json.loads(l) for l in open(out) if l.strip()]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--a", required=True)
    ap.add_argument("--b", required=True)
    ap.add_argument("--opts", default="{}")
    ap.add_argument("--trials", type=int, default=300)
    a = ap.parse_args()
    rows = run_replay(a.cache, json.loads(a.opts), a.trials)
    per_case = []   # (sim swing, real swing, sim t1 swing, real t1 swing, sim VP, real VP)
    cells = []      # (sim delta p_me, real delta own_me) for every objective x turn end
    same = applied = 0
    for r in rows:
        pa, pb = os.path.join(a.a, r["job"] + ".json"), os.path.join(a.b, r["job"] + ".json")
        v = r["v"]["v"]
        if not (os.path.exists(pa) and os.path.exists(pb)) or "trace_alt" not in v:
            continue
        A, B = json.load(open(pa)), json.load(open(pb))
        if A.get("status") != "completed" or B.get("status") != "completed":
            continue
        ovs = B.get("rollout_overrides") or []
        if not ovs or not all(o.get("used") and not o.get("noop") for o in ovs):
            continue
        applied += 1
        me = int(r["player"])
        i_me, i_op = (0, 1) if me == 1 else (1, 0)
        n = len(v["trace"])
        ea, eb = truth_ends(A, n), truth_ends(B, n)
        s_sw = r_sw = s1 = r1 = 0.0
        differs = False
        for k in range(min(n, len(ea), len(eb))):
            for oid, p_plan in v["trace"][k]["own_end"].items():
                p_alt = v["trace_alt"][k]["own_end"][oid]
                oa, ob = int(float(ea[k]["control"].get(oid, 0))), int(float(eb[k]["control"].get(oid, 0)))
                ds = (p_alt[i_me] - p_plan[i_me]) - (p_alt[i_op] - p_plan[i_op])
                dr = ((1 if ob == me else 0) - (1 if oa == me else 0)) - ((1 if ob == 3 - me else 0) - (1 if oa == 3 - me else 0))
                cells.append((ds, dr))
                s_sw += ds
                r_sw += dr
                if k == 0:
                    s1 += ds
                    r1 += dr
                if oa != ob:
                    differs = True
        if not differs:
            same += 1

        def margin(res):
            vp, vs = res["vp"], res["vp_start"]
            g = lambda p: float(vp.get("player%d" % p, {}).get("total", 0)) - float(vs.get("player%d" % p, {}).get("total", 0))
            return g(me) - g(3 - me)
        per_case.append((s_sw, r_sw, s1, r1, float(v.get("pred_vs_plan", 0.0)), margin(B) - margin(A)))
    n = len(per_case)
    print("%d paired cases (alternative applied in both); in %d the real ownership never differs" % (applied, same))
    if n < 8:
        return 0

    def line(label, xs, ys):
        lo, hi = boot_ci(xs, ys)
        print("  %-58s r %+.2f [%+.2f, %+.2f]  rho %+.2f" % (label, corr(xs, ys), lo, hi, spearman(xs, ys)))
    line("ownership swing, this turn end (sim vs real)", [c[2] for c in per_case], [c[3] for c in per_case])
    line("ownership swing, all turn ends in the window", [c[0] for c in per_case], [c[1] for c in per_case])
    line("objective x turn cells", [c[0] for c in cells], [c[1] for c in cells])
    line("VP margin change, one seed (noisy: dice differ after the move)", [c[4] for c in per_case], [c[5] for c in per_case])
    line("real ownership swing -> real VP change (what a perfect sim could get)", [c[1] for c in per_case], [c[5] for c in per_case])
    moved = [c for c in per_case if abs(c[1]) >= 1]
    if moved:
        agree = sum(1 for c in moved if c[0] * c[1] > 0 and abs(c[0]) >= 0.15)
        flat = sum(1 for c in moved if abs(c[0]) < 0.15)
        print("  cases where real ownership swung by a turn or more: %d; sim has the sign on %d, says ~nothing on %d" % (len(moved), agree, flat))
    quiet = [c for c in per_case if c[1] == 0]
    if quiet:
        print("  cases with no real swing: %d; sim also within 0.5 on %d" % (len(quiet), sum(1 for c in quiet if abs(c[0]) < 0.5)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
