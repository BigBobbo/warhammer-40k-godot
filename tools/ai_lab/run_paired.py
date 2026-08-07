#!/usr/bin/env python3
"""M2b — the evaluator. Seed-paired, side-swapped A/B with sequential stopping.

Measuring an AI change is this project's binding constraint, not thinking of
one. Per-seed margin sd is 9-15 VP; the last hand-tuning attempt measured
-2.05 VP with a 95% CI of [-7.2, +3.1], which is to say it measured nothing.
So the design of THIS file matters more than the design of any optimiser that
consumes it.

The arms, following bench_baselines/2026-08-06_mirror_new_vs_old.md:

    margin = VP(P2) - VP(P1)
    F      = structural bias (first turn + board side)
    E      = candidate - baseline, the effect under test

    arm M1:  P1 baseline, P2 candidate   ->  F + E
    arm M2:  P1 candidate, P2 baseline   ->  F - E

    E = (M1 - M2) / 2     cancels F
    F = (M1 + M2) / 2     must agree with a same-fixture A/A arm, or the
                          harness moved rather than the AI

Both arms play the SAME seeds, and since M2a the AI's own RNG is seeded, so a
pair shares its dice, its deck AND its noise draws. That is common random
numbers: the pair difference removes everything except the profile.

SEQUENTIAL STOPPING. Games are the scarce resource, so the driver checks after
each completed pair whether the answer is already clear, and stops if it is.
The stopping rule is fixed BEFORE the run and recorded in the campaign JSON —
the driver decides, never a human watching the numbers, because peeking until
significance is how a noisy measurement produces a confident wrong answer.

Usage:
    python3 tools/ai_lab/run_paired.py --candidate cand.json \\
        --fixture mirror_custodes_postdeploy --max-pairs 24 \\
        --season bench_data/campaign_x
"""
from __future__ import annotations

import argparse
import json
import math
import os
import statistics
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import run_lanes  # noqa: E402
from build_index import find_records, load_record, SCHEMA, _int, _num  # noqa: E402


class Args:
    """run_lanes.run_one takes an args-like object; build one per arm."""
    def __init__(self, **kw):
        self.__dict__.update(kw)


def play_arm(seeds, fixture, arm, p1, p2, season, difficulty, time_scale,
             max_seconds, lanes, stamp, sha):
    a = Args(fixture=fixture, arm=arm, p1_profile=p1, p2_profile=p2,
             difficulty=difficulty, time_scale=time_scale, max_seconds=max_seconds,
             lanes=lanes, seeds="", season=season, skip_gate=True)
    import concurrent.futures
    ud = run_lanes.userdata_dir()
    out = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=lanes) as pool:
        futs = {pool.submit(run_lanes.run_one, s, a, stamp, ud, season, sha): s for s in seeds}
        for f in concurrent.futures.as_completed(futs):
            try:
                out[futs[f]] = f.result()
            except Exception as exc:  # noqa: BLE001
                out[futs[f]] = {"status": "error", "note": str(exc), "seed": futs[f]}
    return out


def margins_by_seed(season: str, arm: str) -> dict:
    """Read margins straight from the records, so a resumed run reuses games."""
    out = {}
    for p in find_records(season):
        try:
            rec = load_record(p)
        except (OSError, ValueError):
            continue
        if rec.get("schema") != SCHEMA:
            continue
        prov, o = rec.get("provenance") or {}, rec.get("outcome") or {}
        if prov.get("arm") != arm or o.get("status") != "completed":
            continue
        out[_int(prov.get("seed"), -1)] = _num(o.get("vp_diff_p2_minus_p1"), 0.0)
    return out


def stats(vals):
    n = len(vals)
    if n == 0:
        return {"n": 0}
    mean = statistics.fmean(vals)
    sd = statistics.stdev(vals) if n > 1 else float("nan")
    se = sd / math.sqrt(n) if n > 1 else float("nan")
    return {"n": n, "mean": round(mean, 3),
            "sd": None if n < 2 else round(sd, 3),
            "se": None if n < 2 else round(se, 3),
            "t": None if (n < 2 or se == 0) else round(mean / se, 3),
            "ci95": None if n < 2 else [round(mean - 1.96 * se, 2),
                                        round(mean + 1.96 * se, 2)]}


def decide(effects, min_pairs, target_effect, futility_se):
    """Fixed stopping rule, evaluated by the driver and never by a human.

    accept   E is at least target_effect and clears 2 standard errors
    reject   E is at most -target_effect and clears 2 standard errors
    futile   the interval is tight enough to exclude target_effect in both
             directions — more games cannot change the conclusion
    """
    s = stats(effects)
    if s["n"] < min_pairs or s.get("se") is None:
        return "continue", s
    # Zero variance across paired seeds means every pair played out identically,
    # which under common random numbers means the candidate changed NOTHING.
    # That is the design document's risk #4: a profile that lints clean but is
    # a no-op (a multiply against an undeclared parameter, a rule whose
    # conditions never hold). Catching it here costs a handful of games instead
    # of a full campaign spent measuring the noise floor.
    if s["se"] == 0:
        return ("no_op" if s["mean"] == 0 else "accept" if s["mean"] >= target_effect
                else "reject" if s["mean"] <= -target_effect else "futile"), s
    lo, hi = s["ci95"]
    if s["mean"] >= target_effect and lo > 0:
        return "accept", s
    if s["mean"] <= -target_effect and hi < 0:
        return "reject", s
    if s["se"] <= futility_se and -target_effect < lo and hi < target_effect:
        return "futile", s
    return "continue", s


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--candidate", required=True, help="candidate profile JSON")
    ap.add_argument("--baseline", default="", help="baseline profile (default: shipped defaults)")
    ap.add_argument("--fixture", default="mirror_custodes_postdeploy")
    ap.add_argument("--season", required=True)
    ap.add_argument("--seed-base", type=int, default=9000)
    ap.add_argument("--max-pairs", type=int, default=24)
    ap.add_argument("--min-pairs", type=int, default=6)
    ap.add_argument("--batch", type=int, default=3, help="pairs per sequential look")
    ap.add_argument("--target-effect", type=float, default=4.0, help="VP/game worth shipping")
    ap.add_argument("--futility-se", type=float, default=1.6)
    ap.add_argument("--lanes", type=int, default=3)
    ap.add_argument("--difficulty", type=int, default=2)
    ap.add_argument("--time-scale", type=float, default=6.0)
    ap.add_argument("--max-seconds", type=float, default=700.0)
    ap.add_argument("--aa-arm", action="store_true",
                    help="also play an A/A arm as a live harness guard")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    season = os.path.abspath(args.season)
    os.makedirs(season, exist_ok=True)
    sha = run_lanes.git_sha()
    stamp = time.strftime("%Y%m%d_%H%M%S")

    if not args.quiet:
        run_lanes.gate_fixture(args.fixture)
        print("=" * 74)
        print("PAIRED A/B  fixture=%s  candidate=%s" % (args.fixture, os.path.basename(args.candidate)))
        print("  stopping rule (fixed in advance): accept/reject at |E| >= %.1f VP and 2 se;"
              % args.target_effect)
        print("  futile once se <= %.2f with the interval inside +/-%.1f; min %d pairs, max %d."
              % (args.futility_se, args.target_effect, args.min_pairs, args.max_pairs))
        print("=" * 74)

    verdict, s = "continue", {"n": 0}
    played = 0
    trajectory = []
    while played < args.max_pairs:
        batch = list(range(args.seed_base + played + 1,
                           args.seed_base + min(played + args.batch, args.max_pairs) + 1))
        if not batch:
            break
        # M1: P1 baseline, P2 candidate. M2: swapped.
        play_arm(batch, args.fixture, "M1", args.baseline, args.candidate, season,
                 args.difficulty, args.time_scale, args.max_seconds, args.lanes, stamp, sha)
        play_arm(batch, args.fixture, "M2", args.candidate, args.baseline, season,
                 args.difficulty, args.time_scale, args.max_seconds, args.lanes, stamp, sha)
        if args.aa_arm:
            play_arm(batch, args.fixture, "AA", args.baseline, args.baseline, season,
                     args.difficulty, args.time_scale, args.max_seconds, args.lanes, stamp, sha)
        played += len(batch)

        m1, m2 = margins_by_seed(season, "M1"), margins_by_seed(season, "M2")
        paired = sorted(set(m1) & set(m2))
        effects = [(m1[s_] - m2[s_]) / 2.0 for s_ in paired]
        biases = [(m1[s_] + m2[s_]) / 2.0 for s_ in paired]
        verdict, s = decide(effects, args.min_pairs, args.target_effect, args.futility_se)
        fstat = stats(biases)
        trajectory.append({"pairs": len(effects), "E": s, "F": fstat, "verdict": verdict})
        if not args.quiet:
            print("  after %2d pair(s): E = %+.2f VP  se %s  CI %s  ->  %s"
                  % (len(effects), s.get("mean", float("nan")),
                     s.get("se"), s.get("ci95"), verdict.upper()))
        if verdict != "continue":
            break

    m1, m2 = margins_by_seed(season, "M1"), margins_by_seed(season, "M2")
    paired = sorted(set(m1) & set(m2))
    effects = [(m1[s_] - m2[s_]) / 2.0 for s_ in paired]
    biases = [(m1[s_] + m2[s_]) / 2.0 for s_ in paired]
    aa = list(margins_by_seed(season, "AA").values()) if args.aa_arm else []

    summary = {
        "schema": "wh40k_paired_campaign", "schema_version": 1,
        "candidate": args.candidate, "baseline": args.baseline,
        "fixture": args.fixture, "git_sha": sha, "difficulty": args.difficulty,
        "stopping_rule": {"target_effect": args.target_effect, "min_pairs": args.min_pairs,
                          "max_pairs": args.max_pairs, "futility_se": args.futility_se,
                          "preregistered": True},
        "pairs": len(effects), "verdict": verdict,
        "effect_E": stats(effects), "bias_F": stats(biases),
        "aa_arm": stats(aa) if aa else None,
        "per_seed": [{"seed": s_, "M1": m1[s_], "M2": m2[s_],
                      "E": (m1[s_] - m2[s_]) / 2.0, "F": (m1[s_] + m2[s_]) / 2.0}
                     for s_ in paired],
        "sequential_trajectory": trajectory,
    }
    # The A/A arm is the harness guard: if F from the paired arms disagrees with
    # a same-fixture A/A, the instrument moved and the effect is not trustworthy.
    if aa and summary["bias_F"].get("se") and summary["aa_arm"].get("se"):
        d = abs(summary["bias_F"]["mean"] - summary["aa_arm"]["mean"])
        se_d = math.sqrt(summary["bias_F"]["se"] ** 2 + summary["aa_arm"]["se"] ** 2)
        summary["harness_drift_se"] = round(d / se_d, 2) if se_d else None
        summary["harness_ok"] = bool(se_d and d / se_d <= 2.0)

    out = os.path.join(season, "campaign_paired_%s_%s.json"
                       % (stamp, os.path.basename(args.candidate).replace(".json", "")))
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2)

    if not args.quiet:
        print("\n" + "=" * 74)
        if verdict == "no_op":
            print("  NOTE: every paired seed played out IDENTICALLY, so this candidate")
            print("        is behaviourally a no-op. Lint it with validate_profile.py —")
            print("        the usual cause is multiply/add on an undeclared parameter.")
        print("VERDICT: %s   after %d pair(s) = %d games"
              % (verdict.upper(), len(effects), len(effects) * (3 if args.aa_arm else 2) * 2))
        e = summary["effect_E"]
        print("  E (candidate - baseline) = %+.2f VP/game   se %s   95%% CI %s"
              % (e.get("mean", float("nan")), e.get("se"), e.get("ci95")))
        print("  F (structural bias)      = %+.2f VP/game   se %s"
              % (summary["bias_F"].get("mean", float("nan")), summary["bias_F"].get("se")))
        if summary.get("harness_drift_se") is not None:
            print("  harness guard: |F_paired - F_AA| = %.2f se  ->  %s"
                  % (summary["harness_drift_se"],
                     "OK" if summary["harness_ok"] else "DRIFT — do not trust this result"))
        print("  campaign: %s" % out)
        print("=" * 74)
    print(json.dumps({"verdict": verdict, "E": summary["effect_E"], "pairs": len(effects)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
