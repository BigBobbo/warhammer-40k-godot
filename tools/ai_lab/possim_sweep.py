#!/usr/bin/env python3
"""Score AIPositionSim option sets against the rollout answer key and the truth.

Inputs (both made once):
  cache  — forecast_prefilter.py --trials 0 --cache DIR   (per-case sim inputs)
  truth  — possim_truth.py --out DIR                      (what really happened)

For each variant {name, opts} this replays every cached case
(40k/tests/possim_replay.gd, milliseconds a case) and reports:
  r vs E     correlation of the predicted effect of the alternative with the
             measured rollout effect (bootstrap 95%), the noise ceiling, and
             sign agreement on the cases the rollouts called clearly
  Brier      turn-by-turn objective ownership of the plan's own line against
             the real game (lower is better; 'still' = nothing changes)
  dead       units expected destroyed per case by the last turn vs really

Usage:
  python3 tools/ai_lab/possim_sweep.py --cache DIR --truth DIR --variants '<json list>' [--trials 600] [--shards 3]
  variants: [{"name": "base", "opts": {}}, {"name": "no damage", "opts": {"damage": false}}]
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
from forecast_prefilter import boot_ci, corr, jobs_from_measured, spearman  # noqa: E402


def vp_link_report(rows: list[dict]) -> str:
    """Real ownership and kills in, VP out: how well the forecast's scoring step
    reproduces what the played game actually scored over the window."""
    pts = []
    for r in rows:
        if "truth_fc" not in r:
            continue
        for X in (1, 2):
            vp, vs = r["truth_vp"].get("player%d" % X, {}), r["truth_vp_start"].get("player%d" % X, {})
            pts.append({"prim_f": r["truth_fc"]["prim%d" % X] - float(vs.get("primary", 0)),
                        "prim_r": float(vp.get("primary", 0)) - float(vs.get("primary", 0)),
                        "sec_f": r["truth_fc"]["sec%d" % X] - float(vs.get("secondary", 0)),
                        "sec_r": float(vp.get("secondary", 0)) - float(vs.get("secondary", 0)),
                        "mission": r["missions"][X - 1]})
    if len(pts) < 6:
        return ""
    out = ["ownership -> VP check (real ownership and kills fed to the forecast; %d player-windows)" % len(pts)]
    for key, label in (("prim", "primary"), ("sec", "secondary")):
        f = [p[key + "_f"] for p in pts]
        rr = [p[key + "_r"] for p in pts]
        out.append("  %-9s VP gained: forecast %.1f vs real %.1f   r = %+.2f   mean abs error %.1f" % (
            label, sum(f) / len(f), sum(rr) / len(rr), corr(f, rr), sum(abs(a - b) for a, b in zip(f, rr)) / len(f)))
    by = {}
    for p in pts:
        by.setdefault(p["mission"], []).append(p)
    for m in sorted(by, key=lambda k: -len(by[k])):
        v = by[m]
        out.append("    %-26s n=%3d primary forecast %.1f / real %.1f" % (m, len(v), sum(p["prim_f"] for p in v) / len(v), sum(p["prim_r"] for p in v) / len(v)))
    return "\n".join(out)


def replay(cache: str, variants: list, trials: int, trace: bool, shards: int, jobs: list[str], truth: str = "") -> list[dict]:
    tmp = tempfile.mkdtemp(prefix="possim_sweep_")
    vp = os.path.join(tmp, "variants.json")
    json.dump(variants, open(vp, "w"))
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/bin") + ":" + env.get("PATH", "")
    procs = []
    for i in range(shards):
        jp = os.path.join(tmp, "jobs_%d.json" % i)
        json.dump(jobs[i::shards], open(jp, "w"))
        cmd = ["godot", "--headless", "--path", os.path.join(REPO, "40k"), "-s", "tests/possim_replay.gd", "--",
               "--cache=" + os.path.abspath(cache), "--jobs=" + jp, "--variants=" + vp,
               "--out=" + os.path.join(tmp, "out_%d.jsonl" % i), "--trials=%d" % trials, "--trace=%d" % (1 if trace else 0)]
        if truth:
            cmd.append("--truth=" + os.path.abspath(truth))
        procs.append(subprocess.Popen(cmd, stdout=open(os.path.join(tmp, "log_%d.txt" % i), "w"), stderr=subprocess.STDOUT, env=env))
    for p in procs:
        p.wait()
    rows = []
    for i in range(shards):
        op = os.path.join(tmp, "out_%d.jsonl" % i)
        if os.path.exists(op):
            rows += [json.loads(l) for l in open(op) if l.strip()]
    return rows


def truth_ends(tr: dict, n: int) -> list:
    ends = [t for t in tr["trace"] if int(t.get("player", 0)) != 0]
    if len(ends) < n:
        ends += [t for t in tr["trace"] if int(t.get("player", 0)) == 0][:1]
    return ends


def score(rows: list[dict], name: str, meta: dict, truth_dir: str, control_now: dict) -> dict:
    out = {"name": name}
    pr = [(r["v"][name]["pred"], meta[r["job"]]) for r in rows if "pred" in r["v"].get(name, {}) and r["job"] in meta]
    if len(pr) >= 5:
        xs = [p for p, _ in pr]
        ys = [m["E"] for _, m in pr]
        lo, hi = boot_ci(xs, ys)
        clear = [(p, m) for p, m in pr if m.get("class") in ("clear", "harmful")]
        out.update({"n": len(pr), "r": corr(xs, ys), "ci": (lo, hi), "rho": spearman(xs, ys),
                    "right": sum(1 for p, m in clear if abs(p) >= 0.25 and (p > 0) == (m["E"] > 0)),
                    "zero": sum(1 for p, m in clear if abs(p) < 0.25), "clear": len(clear),
                    "sd": math.sqrt(sum((x - sum(xs) / len(xs)) ** 2 for x in xs) / len(xs))})
    bs = bp = npt = 0.0
    dead_s = dead_t = 0.0
    used = 0
    by_k: dict = {}
    for r in rows:
        tp = os.path.join(truth_dir, r["job"] + ".json") if truth_dir else ""
        trc = r["v"].get(name, {}).get("trace")
        if not trc or not tp or not os.path.exists(tp):
            continue
        tr = json.load(open(tp))
        if tr.get("status") != "completed" or not tr.get("trace"):
            continue
        used += 1
        me = int(r["player"])
        ends = truth_ends(tr, len(trc))
        now = control_now.get(r["job"], {})
        for k, (srow, trow) in enumerate(zip(trc, ends)):
            for oid, p in srow["own_end"].items():
                owner = int(float(trow["control"].get(oid, 0)))
                y = [1.0 if owner == 1 else 0.0, 1.0 if owner == 2 else 0.0, 1.0 if owner == 0 else 0.0]
                P = [p[0], p[1], max(0.0, 1.0 - p[0] - p[1])]
                cn = int(float(now.get(oid, 0)))
                Q = [0.85 if cn == 1 else 0.075, 0.85 if cn == 2 else 0.075, 0.85 if cn == 0 else 0.075]
                b = sum((P[i] - y[i]) ** 2 for i in range(3))
                bs += b
                bp += sum((Q[i] - y[i]) ** 2 for i in range(3))
                npt += 1
                kk = by_k.setdefault(min(k, 3), [0.0, 0])
                kk[0] += b
                kk[1] += 1
        last_s, last_t = trc[min(len(trc), len(ends)) - 1], ends[min(len(trc), len(ends)) - 1]
        for uid, st in last_s["units"].items():
            tu = last_t["units"].get(uid)
            if tu is not None:
                dead_s += st[1]
                dead_t += 1.0 if tu["share"] <= 0 else 0.0
    if npt:
        out.update({"truth_n": used, "brier": bs / npt, "still": bp / npt,
                    "brier_k": [by_k[k][0] / by_k[k][1] for k in sorted(by_k)],
                    "dead_sim": dead_s / used, "dead_real": dead_t / used})
    return out


def fmt(s: dict) -> str:
    a = "%-22s" % s["name"]
    if "r" in s:
        a += " r %+.2f [%+.2f,%+.2f] rho %+.2f  clear %2d/%2d right, %2d zero  sd %.1f" % (
            s["r"], s["ci"][0], s["ci"][1], s["rho"], s["right"], s["clear"], s["zero"], s["sd"])
    if "brier" in s:
        a += "  | Brier %.3f (still %.3f) by turn %s  dead %.2f/%.2f" % (
            s["brier"], s["still"], " ".join("%.2f" % b for b in s["brier_k"]), s["dead_sim"], s["dead_real"])
    return a


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--truth", default="")
    ap.add_argument("--variants", required=True, help="JSON list, or a file holding one")
    ap.add_argument("--trials", type=int, default=600)
    ap.add_argument("--shards", type=int, default=3)
    ap.add_argument("--no-trace", action="store_true")
    ap.add_argument("--json", default="", help="also write the scores here")
    a = ap.parse_args()
    variants = json.loads(open(a.variants).read() if os.path.exists(a.variants) else a.variants)
    meta = {j["job"]: j for j in jobs_from_measured()}
    jobs = sorted(f[:-4] for f in os.listdir(a.cache) if f.endswith(".var"))
    rows = replay(a.cache, variants, a.trials, not a.no_trace, a.shards, jobs, a.truth)
    control_now = {}
    cn = os.path.join(a.cache, "control_now.json")
    if os.path.exists(cn):
        control_now = json.load(open(cn))
    ys = [meta[j]["E"] for j in jobs if j in meta]
    se2 = [((meta[j]["ci"][1] - meta[j]["ci"][0]) / 3.92) ** 2 for j in jobs if j in meta]
    my = sum(ys) / len(ys)
    var = sum((y - my) ** 2 for y in ys) / (len(ys) - 1)
    print("%d cached cases; noise ceiling for r vs E = %.2f" % (len(jobs), math.sqrt(max(0.0, 1 - (sum(se2) / len(se2)) / var))))
    scores = [score(rows, v["name"], meta, a.truth, control_now) for v in variants]
    for s in scores:
        print(fmt(s))
    link = vp_link_report(rows)
    if link:
        print(link)
    if a.json:
        json.dump(scores, open(a.json, "w"), indent=1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
