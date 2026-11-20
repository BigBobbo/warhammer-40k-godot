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
    lines.append(score_models(ok))
    return "\n".join(lines)


def boot_ci(xs, ys, n=2000, seed=11):
    import random
    rnd = random.Random(seed)
    k = len(xs)
    vals = []
    for _ in range(n):
        idx = [rnd.randrange(k) for _ in range(k)]
        c = corr([xs[i] for i in idx], [ys[i] for i in idx])
        if c == c:
            vals.append(c)
    vals.sort()
    return (vals[int(0.025 * len(vals))], vals[int(0.975 * len(vals))]) if vals else (float("nan"), float("nan"))


def score_models(ok: list[dict], keys=None) -> str:
    """Position look-ahead (AIPositionSim) predictions vs the measured E. The
    measured E is itself noisy (12 seeds a case): `ceiling` is the best r any
    predictor could reach against it."""
    rows = [r for r in ok if r.get("ps_a0") is not None]
    if len(rows) < 5:
        return "  position look-ahead: not run"
    ys = [r["E"] for r in rows]
    se2 = [((r["ci"][1] - r["ci"][0]) / 3.92) ** 2 for r in rows]
    my = sum(ys) / len(ys)
    var = sum((y - my) ** 2 for y in ys) / (len(ys) - 1)
    ceiling = math.sqrt(max(0.0, 1 - (sum(se2) / len(se2)) / var))
    out = ["  position look-ahead vs measured E (n=%d, noise ceiling r = %.2f)" % (len(rows), ceiling),
           "    model            r   [95% boot]     Spearman  clear: right/wrong/zero   top-20% mean E  bottom-20% mean E"]
    clear = [r for r in rows if r.get("class") in ("clear", "harmful")]
    for key in (keys or sorted(k for k in rows[0] if k.startswith("ps_"))):
        xs = [float(r.get(key, 0.0)) for r in rows]
        lo, hi = boot_ci(xs, ys)
        right = sum(1 for r in clear if abs(r[key]) >= 0.25 and (r[key] > 0) == (r["E"] > 0))
        zero = sum(1 for r in clear if abs(r[key]) < 0.25)
        order = sorted(rows, key=lambda r: r[key])
        k = max(1, len(rows) // 5)
        out.append("    %-12s %+.2f  [%+.2f, %+.2f]   %+.2f      %2d / %2d / %2d              %+.2f           %+.2f" % (
            key, corr(xs, ys), lo, hi, spearman(xs, ys), right, len(clear) - right - zero, zero,
            sum(r["E"] for r in order[-k:]) / k, sum(r["E"] for r in order[:k]) / k))
    return "\n".join(out)


def truth_report(rows: list[dict], truth_dir: str) -> str:
    """AIPositionSim's base line vs what really happened (possim_truth.py):
    per turn end, ownership Brier score against the climatology (always
    predicting the overall class frequencies) and expected vs real units lost."""
    pts = []      # (k, [p0, p1, p2] in decider/opponent/nobody order, truth class, persistence class, obj id)
    n_at = {}     # cases that reach turn end k
    deaths = []   # (k, who: "me"|"opp", sim p_dead, truth dead, sim alive, truth share)
    used = 0
    for r in rows:
        tp = os.path.join(truth_dir, r["job"] + ".json")
        if "sim_trace" not in r or not os.path.exists(tp):
            continue
        tr = json.load(open(tp))
        if tr.get("status") != "completed" or not tr.get("trace"):
            continue
        used += 1
        me = int(r["player"])
        # turn_ending rows, plus the stop row when the last turn's turn_ending
        # had not fired before the horizon stopped the game
        ends = [t for t in tr["trace"] if int(t.get("player", 0)) != 0]
        if len(ends) < len(r["sim_trace"]):
            ends += [t for t in tr["trace"] if int(t.get("player", 0)) == 0][:1]
        for k, (srow, trow) in enumerate(zip(r["sim_trace"], ends)):
            n_at[k] = n_at.get(k, 0) + 1
            for oid, pr in srow["own_end"].items():
                owner = int(float(trow["control"].get(oid, 0)))
                p_me, p_op = (pr[0], pr[1]) if me == 1 else (pr[1], pr[0])
                cls = 0 if owner == me else (1 if owner in (1, 2) else 2)
                now = int(float((r.get("control_now") or {}).get(oid, 0)))
                pcls = 0 if now == me else (1 if now in (1, 2) else 2)
                pts.append((k, [p_me, p_op, max(0.0, 1.0 - p_me - p_op)], cls, pcls, oid))
            for uid, st in srow["units"].items():
                tu = trow["units"].get(uid)
                if tu is None:
                    continue
                who = "me" if int(r["sides"].get(uid, 0)) == me else "opp"
                deaths.append((k, who, st[1], 1.0 if tu["share"] <= 0 else 0.0, st[0], tu["share"]))
    if not pts:
        return "  ground truth: no traces matched"
    out = ["  ground truth (%d cases, the AI's own line played once to the horizon)" % used]
    freq = [sum(1 for p in pts if p[2] == c) / len(pts) for c in range(3)]
    out.append("    objectives end up: decider %.0f%%, opponent %.0f%%, nobody %.0f%%" % tuple(100 * f for f in freq))
    out.append("    turn end   ownership Brier: sim / nothing-changes / climatology    sim vs nothing-changes")

    def brier(sel, f):
        return sum(sum((f(p)[c] - (1.0 if p[2] == c else 0.0)) ** 2 for c in range(3)) for p in sel) / len(sel)

    def persist(p):
        return [0.85 if c == p[3] else 0.075 for c in range(3)]
    for k in sorted(set(p[0] for p in pts)) + [-1]:
        sel = [p for p in pts if p[0] == k] if k >= 0 else pts
        bs, bp, bc = brier(sel, lambda p: p[1]), brier(sel, persist), brier(sel, lambda p: freq)
        out.append("      %-3s      %.3f / %.3f / %.3f                              %+.0f%%" % (
            str(k + 1) if k >= 0 else "all", bs, bp, bc, 100 * (1 - bs / bp)))
    for kind in ("home", "nml", "center"):
        sel = [p for p in pts if kind in p[4] and p[0] >= 1]
        if sel:
            out.append("      %-6s (turn end 2+): sim %.3f / nothing-changes %.3f" % (kind, brier(sel, lambda p: p[1]), brier(sel, persist)))
    for lo, hi in ((0.0, 0.2), (0.2, 0.5), (0.5, 0.8), (0.8, 1.01)):
        sel = [p for p in pts if lo <= p[1][0] < hi]
        if sel:
            out.append("    sim says decider holds %.0f-%.0f%%: really %.0f%% (n=%d)" % (
                100 * lo, 100 * min(hi, 1.0), 100 * sum(1 for p in sel if p[2] == 0) / len(sel), len(sel)))
    out.append("    turn end   units dead per case, sim / real (decider's | opponent's)   mean strength left sim / real")
    for k in sorted(set(d[0] for d in deaths)):
        bits = []
        for who in ("me", "opp"):
            sel = [d for d in deaths if d[0] == k and d[1] == who]
            bits.append("%.2f / %.2f" % (sum(d[2] for d in sel) / n_at[k], sum(d[3] for d in sel) / n_at[k]))
        sel = [d for d in deaths if d[0] == k]
        out.append("      %d        %s | %s            %.2f / %.2f" % (k + 1, bits[0], bits[1],
                   sum(d[4] for d in sel) / len(sel), sum(d[5] for d in sel) / len(sel)))
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--trials", type=int, default=600)
    ap.add_argument("--survival", type=int, default=1)
    ap.add_argument("--simopts", default="", help="JSON of AIPositionSim options applied to every variant")
    ap.add_argument("--cache", default="", help="dir to write per-case sim inputs for possim_sweep.py")
    ap.add_argument("--shards", type=int, default=1, help="godot processes to split the cases over")
    ap.add_argument("--truth", default="", help="dir of possim_truth.py traces: score the sim's base line against them")
    ap.add_argument("--out", default="/tmp/forecast_prefilter")
    ap.add_argument("--report", default="")
    a = ap.parse_args()
    if a.report:
        rows = [json.loads(l) for l in open(a.report) if l.strip()]
        meta = {j["job"]: j for j in jobs_from_measured()}
        for r in rows:
            r.update({k: meta.get(r["job"], {}).get(k) for k in ("E", "ci", "class", "n")})
        print(report(rows))
        if a.truth:
            print(truth_report(rows, a.truth))
        return 0
    os.makedirs(a.out, exist_ok=True)
    jobs = jobs_from_measured(a.limit)
    op = os.path.join(a.out, "prefilter.jsonl")
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/bin") + ":" + env.get("PATH", "")
    procs = []
    n_sh = max(1, a.shards)
    for i in range(n_sh):
        jp = os.path.join(a.out, "jobs_%d.json" % i)
        json.dump(jobs[i::n_sh], open(jp, "w"))
        cmd = ["godot", "--headless", "--path", os.path.join(REPO, "40k"), "-s", "tests/forecast_prefilter.gd", "--",
               "--jobs=" + jp, "--out=" + os.path.join(a.out, "prefilter_%d.jsonl" % i),
               "--trials=%d" % a.trials, "--survival=%d" % a.survival]
        if a.simopts:
            cmd.append("--simopts=" + a.simopts)
        if a.cache:
            cmd.append("--cache=" + os.path.abspath(a.cache))
        log = open(os.path.join(a.out, "godot_%d.log" % i), "w")
        procs.append(subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, env=env))
    for pr in procs:
        pr.wait()
    with open(op, "w") as merged:
        for i in range(n_sh):
            part = os.path.join(a.out, "prefilter_%d.jsonl" % i)
            if os.path.exists(part):
                merged.write(open(part).read())
    rows = [json.loads(l) for l in open(op) if l.strip()] if os.path.exists(op) else []
    if a.cache:
        json.dump({r["job"]: r.get("control_now", {}) for r in rows if "control_now" in r},
                  open(os.path.join(a.cache, "control_now.json"), "w"))
    meta = {j["job"]: j for j in jobs}
    for r in rows:
        r.update({k: meta.get(r["job"], {}).get(k) for k in ("E", "ci", "class", "n")})
    print(report(rows))
    if a.truth:
        print(truth_report(rows, a.truth))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
