#!/usr/bin/env python3
"""M2 acceptance test — do two same-seed games play out identically?

Before the AI-layer RNG was seeded, they did not. RulesEngine seeded dice and
the secondary deck, but difficulty score noise ran through the GLOBAL
generator — and it is applied inside a movement-ordering SORT COMPARATOR, so
unit activation order itself was stochastic. Two runs at seed 4242 diverged at
the fifth movement decision and ended as different games: one stalled, one did
not. That made a stall irreproducible from its own seed and killed
common-random-number pairing outright.

This compares two seasons played at the same seeds and reports, per seed,
whether the games are identical at three levels:

  outcome     final VP, margin, rounds, status
  trajectory  the full ordered action log (type + description)
  decisions   every decision record: unit, candidate count, chosen index, score

Trajectory identity is the real bar. Two games can land on the same score by
different routes, and for common-random-number pairing it is the route that
has to match.

Usage:
    python3 tools/ai_lab/determinism_check.py seasonA seasonB
    python3 tools/ai_lab/determinism_check.py seasonA seasonB --json

Exit 0 only if every seed present in both seasons matches at every level.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from build_index import find_records, load_record, SCHEMA, _int  # noqa: E402


def by_seed(season: str) -> dict:
    out = {}
    for p in find_records(season):
        try:
            rec = load_record(p)
        except (OSError, ValueError):
            continue
        if rec.get("schema") != SCHEMA:
            continue
        out[_int((rec.get("provenance") or {}).get("seed"), -1)] = rec
    return out


def outcome_key(rec: dict) -> dict:
    o = rec.get("outcome") or {}
    vp = o.get("vp") or {}
    return {
        "status": o.get("status"),
        "winner": o.get("winner"),
        "margin": o.get("vp_diff_p2_minus_p1"),
        "rounds": o.get("battle_round"),
        "actions": o.get("actions_taken"),
        "vp_p1": (vp.get("player1") or {}).get("total"),
        "vp_p2": (vp.get("player2") or {}).get("total"),
    }


def trajectory(rec: dict) -> list:
    return ["%s|%s|%s" % (e.get("phase"), e.get("action_type"), e.get("description"))
            for e in (rec.get("action_log") or [])]


def decision_fingerprint(rec: dict) -> list:
    out = []
    for b in rec.get("decisions") or []:
        for r in b.get("records") or []:
            cands = r.get("candidates") or []
            out.append("%s|%s|%s|%s|%d|%d|%s" % (
                b.get("round"), b.get("phase_name"), b.get("player"),
                r.get("unit_id"), len(cands), _int(r.get("chosen_index"), -1),
                # scores to 6dp: noise lives in the 1st decimal, so this is strict
                ",".join("%.6f" % float(c.get("score", 0) or 0) for c in cands)))
    return out


def first_divergence(a: list, b: list):
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return i, x, y
    if len(a) != len(b):
        i = min(len(a), len(b))
        return i, (a[i] if i < len(a) else "<end>"), (b[i] if i < len(b) else "<end>")
    return None


def compare(a: dict, b: dict) -> dict:
    res = {"seed": _int((a.get("provenance") or {}).get("seed"), -1)}
    res["outcome_match"] = outcome_key(a) == outcome_key(b)
    res["outcome_a"] = outcome_key(a)
    res["outcome_b"] = outcome_key(b)

    ta, tb = trajectory(a), trajectory(b)
    res["actions_a"], res["actions_b"] = len(ta), len(tb)
    d = first_divergence(ta, tb)
    res["trajectory_match"] = d is None
    if d:
        res["trajectory_divergence"] = {"index": d[0], "a": d[1][:110], "b": d[2][:110]}

    da, db = decision_fingerprint(a), decision_fingerprint(b)
    res["decisions_a"], res["decisions_b"] = len(da), len(db)
    d2 = first_divergence(da, db)
    res["decisions_match"] = d2 is None
    if d2:
        res["decision_divergence"] = {"index": d2[0], "a": d2[1][:110], "b": d2[2][:110]}
    return res


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("season_a")
    ap.add_argument("season_b")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    A, B = by_seed(args.season_a), by_seed(args.season_b)
    seeds = sorted(set(A) & set(B))
    if not seeds:
        raise SystemExit("no seeds common to both seasons (A=%s B=%s)"
                         % (sorted(A), sorted(B)))

    results = [compare(A[s], B[s]) for s in seeds]
    if args.json:
        print(json.dumps(results, indent=2))
        return 0 if all(r["trajectory_match"] and r["decisions_match"] for r in results) else 1

    print("=" * 74)
    print("DETERMINISM CHECK — %d seed(s) played twice" % len(seeds))
    print("=" * 74)
    print("\n  %-8s %-9s %-11s %-11s %s" % ("seed", "outcome", "trajectory", "decisions", "actions A/B"))
    for r in results:
        print("  %-8d %-9s %-11s %-11s %d/%d" % (
            r["seed"],
            "match" if r["outcome_match"] else "DIFFER",
            "match" if r["trajectory_match"] else "DIFFER",
            "match" if r["decisions_match"] else "DIFFER",
            r["actions_a"], r["actions_b"]))

    bad = [r for r in results if not (r["trajectory_match"] and r["decisions_match"])]
    for r in bad:
        print("\n  seed %d first divergence:" % r["seed"])
        for k, label in (("decision_divergence", "decision"), ("trajectory_divergence", "action")):
            if k in r:
                d = r[k]
                print("    %s #%d" % (label, d["index"]))
                print("      A: %s" % d["a"])
                print("      B: %s" % d["b"])

    ok = not bad
    print("\n" + "=" * 74)
    if ok:
        total = sum(r["actions_a"] for r in results)
        print("PASS — %d seed(s) reproduce EXACTLY: %d action lines and %d decision"
              % (len(seeds), total, sum(r["decisions_a"] for r in results)))
        print("       records identical across independent runs.")
        print("       Common-random-number pairing is now sound, a stall reproduces")
        print("       from its own seed, and single-rollout counterfactuals are valid.")
    else:
        print("FAIL — %d of %d seed(s) diverged. Same-seed replay is NOT exact;"
              % (len(bad), len(seeds)))
        print("       paired evaluation must not assume common random numbers.")
    print("=" * 74)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
