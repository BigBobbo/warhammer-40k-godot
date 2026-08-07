#!/usr/bin/env python3
"""B0 — measure a candidate against the FROZEN baseline, not against today.

Every comparison in this repo so far has been candidate-vs-current. That is a
moving target: a change measured at +2 VP against a version that had itself
drifted tells you nothing about whether the AI is better than it was in
August. Progress needs an opponent that never improves.

`40k/data/ai_profiles/baseline_2026_08.json` is that opponent — the incumbent's
values for every parameter in the manifest, written out explicitly so a later
change to a `const` default cannot move the baseline underneath a comparison.

This is a thin, deliberate wrapper over run_paired.py: same side-swapped pairing,
same pre-registered stopping rule, same statistics. The only thing it adds is
that the baseline arm is pinned to a file instead of to "whatever the defaults
are today", and that the report says which freeze it was measured against.

Usage:
    python3 tools/ai_lab/vs_baseline.py --candidate cand.json --season s/
    python3 tools/ai_lab/vs_baseline.py --candidate cand.json --season s/ \\
        --fixture mirror_orks_postdeploy --min-pairs 8 --max-pairs 24
    python3 tools/ai_lab/vs_baseline.py --selftest      # frozen vs frozen = 0.00
"""
from __future__ import annotations

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import run_paired  # noqa: E402

BASELINE = os.path.join(REPO, "40k", "data", "ai_profiles", "baseline_2026_08.json")


def baseline_info(path: str = BASELINE) -> dict:
    with open(path, encoding="utf-8") as fh:
        prof = json.load(fh)
    return {
        "profile_name": prof.get("profile_name", "?"),
        "frozen_at": prof.get("frozen_at", {}),
        "parameters": len(prof.get("parameters", {})),
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--candidate", default="")
    ap.add_argument("--season", default="")
    ap.add_argument("--baseline", default=BASELINE,
                    help="which freeze to measure against (default: 2026-08)")
    ap.add_argument("--fixture", default="mirror_custodes_postdeploy")
    ap.add_argument("--min-pairs", type=int, default=8)
    ap.add_argument("--max-pairs", type=int, default=24)
    ap.add_argument("--lanes", type=int, default=3)
    ap.add_argument("--seed-base", type=int, default=31000)
    ap.add_argument("--difficulty", type=int, default=2)
    ap.add_argument("--max-seconds", type=float, default=700.0)
    ap.add_argument("--selftest", action="store_true",
                    help="frozen vs frozen. E must be exactly 0.00 — if it is not, "
                         "the baseline is not pinning what it claims to pin.")
    args = ap.parse_args(argv)

    info = baseline_info(args.baseline)
    candidate = args.candidate
    season = args.season
    min_pairs, max_pairs = args.min_pairs, args.max_pairs
    if args.selftest:
        candidate = args.baseline
        season = season or os.path.join(REPO, "bench_data", "vs_baseline_selftest")
        min_pairs, max_pairs = 3, 3
    if not candidate or not season:
        ap.error("--candidate and --season are required (or use --selftest)")

    print("=" * 74)
    print("VS FROZEN BASELINE")
    print("  baseline : %s" % info["profile_name"])
    print("  frozen at: %s (%s), %d parameters"
          % (info["frozen_at"].get("git_sha", "?"), info["frozen_at"].get("date", "?"),
             info["parameters"]))
    print("  candidate: %s" % os.path.basename(candidate))
    print("  fixture  : %s" % args.fixture)
    print("=" * 74)

    rc = run_paired.main([
        "--candidate", candidate, "--baseline", args.baseline,
        "--fixture", args.fixture, "--season", season,
        "--min-pairs", str(min_pairs), "--max-pairs", str(max_pairs),
        "--lanes", str(args.lanes), "--seed-base", str(args.seed_base),
        "--difficulty", str(args.difficulty), "--max-seconds", str(args.max_seconds),
    ])

    if args.selftest:
        # run_paired prints its own machine-readable line; re-read the campaign
        # so the selftest asserts rather than trusting the eyeball.
        newest, newest_mtime = None, -1.0
        for name in os.listdir(season):
            if name.startswith("campaign_paired_") and name.endswith(".json"):
                p = os.path.join(season, name)
                if os.path.getmtime(p) > newest_mtime:
                    newest, newest_mtime = p, os.path.getmtime(p)
        if newest is None:
            print("\nSELFTEST FAIL — no campaign file written")
            return 1
        with open(newest, encoding="utf-8") as fh:
            camp = json.load(fh)
        # run_paired writes the effect under `effect_E` (its stdout summary
        # calls it `E`; the campaign file is the authority).
        E = (camp.get("effect_E") or camp.get("E") or {})
        if "mean" not in E:
            print("\nSELFTEST FAIL — campaign file has no effect: keys=%s" % sorted(camp.keys()))
            return 1
        mean, se = float(E["mean"]), float(E.get("se") or 0.0)
        ok = abs(mean) < 1e-9 and abs(se) < 1e-9 and camp.get("verdict") == "no_op"
        print("\nSELFTEST: frozen vs frozen  E = %+.2f  se = %.2f  ->  %s"
              % (mean, se, "PASS" if ok else "FAIL"))
        if not ok:
            print("  A frozen profile played against itself must be a NO-OP. A")
            print("  non-zero effect means the baseline is not pinning the values")
            print("  it claims to, or the pairing is not sharing random numbers.")
        return 0 if ok else 1

    return rc


if __name__ == "__main__":
    raise SystemExit(main())
