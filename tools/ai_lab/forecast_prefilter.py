#!/usr/bin/env python3
"""Can the game forecast screen rollout candidates? Predicted vs measured.

For every MEASURED movement rollout in r4_designs/measured_positions.json whose
alternative redirects one unit to another objective, 40k/tests/forecast_prefilter.gd
rebuilds the AI's movement plan in the saved position and forecasts the final
margin of the plan with and without the redirect (AIForecast.gd, the
projection FORECAST-PLAN uses). This tool joins those predictions with the
measured effect E (alternative minus the AI's choice, VP, rollouts over
12-36 seeds) and reports correlation, sign agreement on the cases the
rollouts called clearly, and how a "forecast says >= X" screen would have
sorted them.

Usage:
    python3 tools/ai_lab/forecast_prefilter.py [--limit N] [--trials 600] [--out DIR]
    python3 tools/ai_lab/forecast_prefilter.py --report DIR/prefilter.jsonl
"""
from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MEASURED = os.path.join(HERE, "r4_designs", "measured_positions.json")


def jobs_from_measured(limit: int = 0) -> list[dict]:
    out = []
    for x in json.load(open(MEASURED)):
        alt = x.get("alt") or []
        if x.get("kind") != "movement" or len(alt) != 1 or alt[0].get("kind") != "move" or not alt[0].get("objective"):
            continue
        out.append({"job": x["job"], "case": x["case"], "unit": alt[0]["unit"], "objective": alt[0]["objective"],
                    "mode": alt[0].get("mode", ""), "E": x.get("E"), "ci": x.get("ci"), "class": x.get("class", ""),
                    "n": x.get("n")})
    return out[:limit] if limit else out


def corr(xs, ys):
    n = len(xs)
    if n < 3:
        return float("nan")
    mx, my = sum(xs) / n, sum(ys) / n
    sx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    sy = math.sqrt(sum((y - my) ** 2 for y in ys))
    return float("nan") if sx == 0 or sy == 0 else sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (sx * sy)


def spearman(xs, ys):
    def ranks(v):
        order = sorted(range(len(v)), key=lambda i: v[i])
        r = [0.0] * len(v)
        i = 0
        while i < len(order):
            j = i
            while j + 1 < len(order) and v[order[j + 1]] == v[order[i]]:
                j += 1
            for k in range(i, j + 1):
                r[order[k]] = (i + j) / 2.0
            i = j + 1
        return r
    return corr(ranks(xs), ranks(ys))


def report(rows: list[dict]) -> str:
    ok = [r for r in rows if "pred" in r and r.get("E") is not None]
    lines = ["forecast pre-filter: %d of %d measured movement cases priced" % (len(ok), len(rows))]
    errs: dict = {}
    for r in rows:
        if "error" in r:
            errs[r["error"].split(" (")[0]] = errs.get(r["error"].split(" (")[0], 0) + 1
    if errs:
        lines.append("  not priced: " + ", ".join("%s x%d" % kv for kv in sorted(errs.items())))
    if len(ok) < 3:
        return "\n".join(lines)
    xs = [r["pred"] for r in ok]
    ys = [r["E"] for r in ok]
    lines.append("  Pearson r(pred, E) = %+.2f   Spearman = %+.2f   (n=%d)" % (corr(xs, ys), spearman(xs, ys), len(ok)))
    moved = [r for r in ok if r.get("cells_changed")]
    lines.append("  cases where the redirect changes projected ownership: %d (r = %+.2f)" % (
        len(moved), corr([r["pred"] for r in moved], [r["E"] for r in moved]) if len(moved) >= 3 else float("nan")))
    clear = [r for r in ok if r.get("class") in ("clear", "harmful")]
    agree = sum(1 for r in clear if (r["pred"] > 0) == (r["E"] > 0) and r["pred"] != 0)
    flat = sum(1 for r in clear if r["pred"] == 0)
    lines.append("  rollout-clear cases (CI excludes 0): %d; forecast sign agrees on %d, predicts 0 on %d" % (len(clear), agree, flat))
    for th in (0.5, 1.0, 2.0):
        pos = [r for r in ok if r["pred"] >= th]
        neg = [r for r in ok if r["pred"] < th]
        mp = sum(r["E"] for r in pos) / len(pos) if pos else float("nan")
        mn = sum(r["E"] for r in neg) / len(neg) if neg else float("nan")
        lines.append("  screen pred >= %.1f: %3d pass (mean measured E %+.2f) / %3d rejected (mean E %+.2f)" % (th, len(pos), mp, len(neg), mn))
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--trials", type=int, default=600)
    ap.add_argument("--survival", type=int, default=1)
    ap.add_argument("--out", default="/tmp/forecast_prefilter")
    ap.add_argument("--report", default="")
    a = ap.parse_args()
    if a.report:
        rows = [json.loads(l) for l in open(a.report) if l.strip()]
        meta = {j["job"]: j for j in jobs_from_measured()}
        for r in rows:
            r.update({k: meta.get(r["job"], {}).get(k) for k in ("E", "ci", "class", "n")})
        print(report(rows))
        return 0
    os.makedirs(a.out, exist_ok=True)
    jobs = jobs_from_measured(a.limit)
    jp = os.path.join(a.out, "jobs.json")
    op = os.path.join(a.out, "prefilter.jsonl")
    json.dump(jobs, open(jp, "w"))
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/bin") + ":" + env.get("PATH", "")
    cmd = ["godot", "--headless", "--path", os.path.join(REPO, "40k"), "-s", "tests/forecast_prefilter.gd", "--",
           "--jobs=" + jp, "--out=" + op, "--trials=%d" % a.trials, "--survival=%d" % a.survival]
    log = open(os.path.join(a.out, "godot.log"), "w")
    subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, env=env, check=False)
    rows = [json.loads(l) for l in open(op) if l.strip()] if os.path.exists(op) else []
    meta = {j["job"]: j for j in jobs}
    for r in rows:
        r.update({k: meta.get(r["job"], {}).get(k) for k in ("E", "ci", "class", "n")})
    print(report(rows))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
