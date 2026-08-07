#!/usr/bin/env python3
"""The accept/reject gate. A candidate ships only if it clears every check.

Optimising VP margin is optimising a PROXY. A search that beats it can do so
by playing degenerately, by exploiting an engine bug, or by fitting one
matchup. So a measured effect is necessary and nowhere near sufficient, and
this file is deliberately the last word rather than the driver's.

The gates, from the design document's success metric and risk register:

  1. TWO-MATCHUP GRID       >= target VP pooled across both mirrors at 2 se,
                            and no single matchup worse than -2 VP at 1 se.
                            A weight that wins an Ork mirror need not transfer.
  2. NO STALL REGRESSION    stalls are a hard gate: the same seeds must not
                            produce more of them. A "win" that freezes games
                            is not a win.
  3. SCENARIO SUITE         zero new failures in the windowed scenarios, which
                            are the project's correctness gate.
  4. ACTION-MIX GUARDRAIL   the distribution of action types must not drift
                            far from baseline. This is the Goodhart check: if
                            the AI stops charging entirely and wins on points,
                            the number improved and the game got worse.
  5. INTERPRETABILITY       every changed parameter stays within the campaign
                            cap, so the diff is readable and the AI's narrated
                            reasoning stays truthful.

Usage:
    python3 tools/ai_lab/gate_candidate.py --candidate cem_best.json \\
        --season bench_data/gate1 --pairs 18
"""
from __future__ import annotations

import argparse
import collections
import json
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

from build_index import find_records, load_record, SCHEMA, _int  # noqa: E402
from params_manifest import build_manifest  # noqa: E402

MIRRORS = ["mirror_orks_postdeploy", "mirror_custodes_postdeploy"]


def run_paired(candidate, fixture, season, pairs, seed_base, lanes, max_seconds, difficulty):
    cmd = [sys.executable, os.path.join(HERE, "run_paired.py"),
           "--candidate", candidate, "--fixture", fixture, "--season", season,
           "--seed-base", str(seed_base), "--min-pairs", str(pairs),
           "--max-pairs", str(pairs), "--batch", str(max(1, pairs // 2)),
           "--lanes", str(lanes), "--max-seconds", str(max_seconds),
           "--difficulty", str(difficulty), "--aa-arm", "--quiet"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    for line in reversed(r.stdout.strip().splitlines()):
        try:
            return json.loads(line)
        except ValueError:
            continue
    return {"verdict": "error", "E": {"n": 0}, "stderr": r.stderr[-400:]}


def season_stats(season: str) -> dict:
    """Stall counts and action-type mix per arm, straight from the records."""
    stalls = collections.Counter()
    games = collections.Counter()
    mix = collections.defaultdict(collections.Counter)
    for p in find_records(season):
        try:
            rec = load_record(p)
        except (OSError, ValueError):
            continue
        if rec.get("schema") != SCHEMA:
            continue
        arm = (rec.get("provenance") or {}).get("arm", "?")
        games[arm] += 1
        if (rec.get("outcome") or {}).get("status") != "completed":
            stalls[arm] += 1
        for e in rec.get("action_log") or []:
            mix[arm][e.get("action_type", "?")] += 1
    return {"stalls": dict(stalls), "games": dict(games),
            "mix": {a: dict(c) for a, c in mix.items()}}


def mix_drift(mix_a: dict, mix_b: dict) -> float:
    """Total-variation distance between two action-type distributions (0..1)."""
    ta, tb = sum(mix_a.values()), sum(mix_b.values())
    if not ta or not tb:
        return 0.0
    keys = set(mix_a) | set(mix_b)
    return 0.5 * sum(abs(mix_a.get(k, 0) / ta - mix_b.get(k, 0) / tb) for k in keys)


def run_scenarios() -> dict:
    """The windowed scenario suite — the project's correctness gate."""
    script = os.path.join(REPO, "40k", "tests", "run_scenarios.sh")
    if not os.path.exists(script):
        return {"ran": False, "reason": "run_scenarios.sh not found"}
    r = subprocess.run(["bash", script], cwd=os.path.join(REPO, "40k"),
                       capture_output=True, text=True, timeout=7200)
    tail = (r.stdout or "")[-4000:]
    return {"ran": True, "returncode": r.returncode, "passed": r.returncode == 0,
            "tail": tail}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--season", required=True)
    ap.add_argument("--pairs", type=int, default=18,
                    help="paired seeds per mirror (18 pairs = 36 games, the design "
                         "document's sample for resolving 4 VP at 2 se)")
    ap.add_argument("--target", type=float, default=4.0)
    ap.add_argument("--max-regression", type=float, default=2.0)
    ap.add_argument("--max-mix-drift", type=float, default=0.15)
    ap.add_argument("--max-change", type=float, default=0.5)
    ap.add_argument("--seed-base", type=int, default=60000)
    ap.add_argument("--lanes", type=int, default=3)
    ap.add_argument("--difficulty", type=int, default=2)
    ap.add_argument("--max-seconds", type=float, default=700.0)
    ap.add_argument("--skip-scenarios", action="store_true",
                    help="skip gate 3 (records it as NOT RUN, never as passed)")
    args = ap.parse_args(argv)

    season = os.path.abspath(args.season)
    os.makedirs(season, exist_ok=True)
    with open(args.candidate) as fh:
        cand = json.load(fh)

    report = {"candidate": args.candidate, "gates": {}, "per_mirror": {}}
    print("=" * 78)
    print("GATE — %s" % os.path.basename(args.candidate))
    print("=" * 78)

    # ---- gate 1: two-matchup grid ------------------------------------------
    seed_base = args.seed_base
    per = {}
    for fixture in MIRRORS:
        sub = os.path.join(season, fixture)
        res = run_paired(args.candidate, fixture, sub, args.pairs, seed_base,
                         args.lanes, args.max_seconds, args.difficulty)
        seed_base += args.pairs + 50
        per[fixture] = res
        e = res.get("E", {})
        print("  %-30s E = %+7s  se %-6s  CI %s  (%s)"
              % (fixture, e.get("mean"), e.get("se"), e.get("ci95"), res.get("verdict")))
    report["per_mirror"] = per

    means = [per[f].get("E", {}).get("mean") for f in MIRRORS]
    ses = [per[f].get("E", {}).get("se") for f in MIRRORS]
    if all(m is not None for m in means) and all(s not in (None, 0) for s in ses):
        pooled = sum(means) / len(means)
        pooled_se = math.sqrt(sum(s ** 2 for s in ses)) / len(ses)
        worst = min(means)
        worst_i = means.index(worst)
        grid_ok = (pooled >= args.target and pooled - 2 * pooled_se > 0
                   and worst + ses[worst_i] >= -args.max_regression)
    else:
        # A no_op candidate has se 0 by construction; that is a fail, not an error.
        pooled = sum(m for m in means if m is not None) / max(1, len([m for m in means if m is not None]))
        pooled_se, worst, grid_ok = 0.0, min([m for m in means if m is not None] or [0]), False
    report["gates"]["grid"] = {"pooled_E": round(pooled, 3), "pooled_se": round(pooled_se, 3),
                               "worst_matchup": worst, "target": args.target, "pass": bool(grid_ok)}
    print("\n  [%s] gate 1 grid: pooled E = %+.2f +/- %.2f se, worst matchup %+.2f"
          % ("PASS" if grid_ok else "FAIL", pooled, pooled_se, worst))

    # ---- gates 2 and 4: stalls and action mix ------------------------------
    stall_ok, mix_ok, drifts, stall_detail = True, True, {}, {}
    for fixture in MIRRORS:
        st = season_stats(os.path.join(season, fixture))
        base_g, cand_g = st["games"].get("M2", 0), st["games"].get("M1", 0)
        base_s, cand_s = st["stalls"].get("M2", 0), st["stalls"].get("M1", 0)
        stall_detail[fixture] = {"baseline_side_stalls": base_s, "candidate_side_stalls": cand_s,
                                 "games_per_arm": {"M1": cand_g, "M2": base_g}}
        # both arms contain the candidate on one side, so compare against the A/A arm
        aa_s, aa_g = st["stalls"].get("AA", 0), st["games"].get("AA", 0)
        rate_aa = (aa_s / aa_g) if aa_g else 0.0
        rate_ab = ((base_s + cand_s) / (base_g + cand_g)) if (base_g + cand_g) else 0.0
        stall_detail[fixture]["aa_rate"] = round(rate_aa, 3)
        stall_detail[fixture]["ab_rate"] = round(rate_ab, 3)
        if rate_ab > rate_aa + 0.05:
            stall_ok = False
        d = mix_drift(st["mix"].get("AA", {}), st["mix"].get("M1", {}))
        drifts[fixture] = round(d, 4)
        if d > args.max_mix_drift:
            mix_ok = False
    report["gates"]["stalls"] = {"detail": stall_detail, "pass": stall_ok}
    report["gates"]["action_mix"] = {"drift": drifts, "max": args.max_mix_drift, "pass": mix_ok}
    print("  [%s] gate 2 stalls: %s" % ("PASS" if stall_ok else "FAIL",
          {f: (stall_detail[f]["ab_rate"], stall_detail[f]["aa_rate"]) for f in MIRRORS}))
    print("  [%s] gate 4 action mix drift: %s (max %.2f)"
          % ("PASS" if mix_ok else "FAIL", drifts, args.max_mix_drift))

    # ---- gate 5: interpretability ------------------------------------------
    manifest = build_manifest()["parameters"]
    over = []
    for n, v in (cand.get("parameters") or {}).items():
        d = manifest.get(n, {}).get("default")
        if d in (None, 0):
            continue
        if abs(float(v) - float(d)) / abs(float(d)) > args.max_change + 1e-9:
            over.append((n, d, v))
    interp_ok = not over
    report["gates"]["interpretability"] = {"over_cap": over, "cap": args.max_change,
                                           "pass": interp_ok}
    print("  [%s] gate 5 interpretability: %d parameter(s) beyond the +/-%.0f%% cap"
          % ("PASS" if interp_ok else "FAIL", len(over), args.max_change * 100))

    # ---- gate 3: scenario suite --------------------------------------------
    if args.skip_scenarios:
        scen = {"ran": False, "reason": "--skip-scenarios"}
        scen_ok = False
        print("  [NOT RUN] gate 3 scenario suite — skipped, so this candidate CANNOT ship")
    else:
        print("  ... gate 3: running the windowed scenario suite (this takes a while)")
        scen = run_scenarios()
        scen_ok = bool(scen.get("passed"))
        print("  [%s] gate 3 scenario suite" % ("PASS" if scen_ok else "FAIL"))
    report["gates"]["scenarios"] = {**scen, "pass": scen_ok}

    accepted = all([grid_ok, stall_ok, mix_ok, interp_ok, scen_ok])
    report["accepted"] = accepted
    out = os.path.join(season, "gate_report.json")
    with open(out, "w") as fh:
        json.dump(report, fh, indent=2)

    print("\n" + "=" * 78)
    print("VERDICT: %s" % ("ACCEPTED — safe to ship" if accepted else "REJECTED"))
    if not accepted:
        failed = [k for k, v in report["gates"].items() if not v.get("pass")]
        print("  failed gate(s): %s" % ", ".join(failed))
    print("  report: %s" % out)
    print("=" * 78)
    return 0 if accepted else 1


if __name__ == "__main__":
    sys.exit(main())
