#!/usr/bin/env python3
"""M4 — cross-entropy search over the parameters M3 found to matter.

Why CEM and not something cleverer. At this noise level the learner only needs
to ORDER candidates, not estimate their values, and paired evaluation gives
ordering cheaply. CEM is rank-based, so it is unusually robust to a noisy
objective; it is embarrassingly parallel at exactly the 3-lane concurrency the
box has; its whole state is a JSON file, so a campaign resumes after any
interruption; and its output is a distribution over named constants, which a
person can read as a profile diff. SPSA's gain sequences are fragile against
+/-8 VP noise, and a GP in 15 dimensions with this much noise spends the
budget fitting the noise.

The loop:

    1. sample a population from N(mu, sigma) per parameter, clamped to bounds
    2. RACE: evaluate everyone cheaply, keep the better half
    3. evaluate the survivors harder
    4. refit mu/sigma to the elite fraction
    5. repeat, tracking the best candidate ever seen

Racing matters more than the optimiser. Most sampled candidates are bad, and
finding out cheaply is the difference between a campaign that fits in a day
and one that does not.

Guardrails, all from the design document's risk register:
  * every candidate is linted before it costs a single game (risk #4)
  * per-parameter change is capped per campaign, so an accepted diff stays
    readable and the AI's narration stays truthful (risk #10)
  * a `no_op` verdict is recorded as such, never as "zero effect"
  * every generation is written to disk before the next one starts

Usage:
    python3 tools/ai_lab/cem_driver.py --season bench_data/cem1 \\
        --params-from bench_data/screen1/screen_results.json
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

from params_manifest import build_manifest  # noqa: E402


def lint(profile_path) -> tuple:
    r = subprocess.run([sys.executable, os.path.join(HERE, "validate_profile.py"),
                        profile_path], capture_output=True, text=True)
    return r.returncode == 0, r.stdout


def write_profile(path, name, params, description):
    with open(path, "w") as fh:
        json.dump({"format": "wh40k_ai_profile", "version": 1, "profile_name": name,
                   "description": description, "parameters": params, "rules": []},
                  fh, indent=2)


def evaluate(profile, fixture, season, pairs, seed_base, lanes, max_seconds, difficulty):
    cmd = [sys.executable, os.path.join(HERE, "run_paired.py"),
           "--candidate", profile, "--fixture", fixture, "--season", season,
           "--seed-base", str(seed_base), "--min-pairs", str(pairs),
           "--max-pairs", str(pairs), "--batch", str(pairs), "--lanes", str(lanes),
           "--max-seconds", str(max_seconds), "--difficulty", str(difficulty), "--quiet"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    for line in reversed(r.stdout.strip().splitlines()):
        try:
            return json.loads(line)
        except ValueError:
            continue
    return {"verdict": "error", "E": {"n": 0, "mean": None}, "stderr": r.stderr[-300:]}


def pick_params(args, manifest) -> list:
    if args.params:
        names = [p.strip() for p in args.params.split(",") if p.strip()]
    elif args.params_from:
        with open(args.params_from) as fh:
            screen = json.load(fh)
        names = [r["param"] for r in screen["results"]
                 if not r.get("no_op") and r.get("influence", 0) >= args.min_influence]
        names = names[: args.dims]
    else:
        raise SystemExit("give --params or --params-from (an M3 screen_results.json)")
    return [n for n in names if n in manifest and manifest[n]["default"] is not None]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--season", required=True)
    ap.add_argument("--params", default="")
    ap.add_argument("--params-from", default="")
    ap.add_argument("--min-influence", type=float, default=1.0)
    ap.add_argument("--dims", type=int, default=12)
    ap.add_argument("--fixture", default="mirror_custodes_2000_postdeploy")
    ap.add_argument("--population", type=int, default=8)
    ap.add_argument("--elite", type=int, default=3)
    ap.add_argument("--generations", type=int, default=5)
    ap.add_argument("--race-pairs", type=int, default=3, help="cheap first look")
    ap.add_argument("--final-pairs", type=int, default=6, help="pairs for race survivors")
    ap.add_argument("--sigma0", type=float, default=0.25, help="initial sd, as a fraction of default")
    ap.add_argument("--max-change", type=float, default=0.5,
                    help="cap per parameter per campaign (risk #10: keep diffs readable)")
    ap.add_argument("--seed-base", type=int, default=40000)
    ap.add_argument("--lanes", type=int, default=3)
    ap.add_argument("--difficulty", type=int, default=2)
    ap.add_argument("--max-seconds", type=float, default=400.0)
    ap.add_argument("--rng-seed", type=int, default=12345)
    args = ap.parse_args(argv)

    manifest = build_manifest()["parameters"]
    names = pick_params(args, manifest)
    if not names:
        raise SystemExit("no usable parameters selected")

    rng = random.Random(args.rng_seed)
    season = os.path.abspath(args.season)
    prof_dir = os.path.join(season, "_profiles")
    os.makedirs(prof_dir, exist_ok=True)

    defaults = {n: float(manifest[n]["default"]) for n in names}
    mu = dict(defaults)
    sigma = {n: abs(defaults[n]) * args.sigma0 or args.sigma0 for n in names}
    lo = {n: defaults[n] * (1.0 - args.max_change) for n in names}
    hi = {n: defaults[n] * (1.0 + args.max_change) for n in names}
    for n in names:                      # negative defaults invert the bounds
        if lo[n] > hi[n]:
            lo[n], hi[n] = hi[n], lo[n]

    print("=" * 78)
    print("CEM CAMPAIGN — %d dims, pop %d, elite %d, %d generations"
          % (len(names), args.population, args.elite, args.generations))
    print("  fixture=%s  race %d pairs -> survivors %d pairs"
          % (args.fixture, args.race_pairs, args.final_pairs))
    print("  per-parameter change capped at +/-%.0f%% for this campaign" % (args.max_change * 100))
    print("  dims: %s" % ", ".join(names))
    print("=" * 78)

    seed_base = args.seed_base
    best = {"E": None, "params": None, "profile": None, "verdict": None}
    history = []
    t0 = time.time()

    for gen in range(1, args.generations + 1):
        print("\n--- generation %d/%d ---" % (gen, args.generations))
        pop = []
        for k in range(args.population):
            params = {}
            for n in names:
                v = rng.gauss(mu[n], sigma[n])
                params[n] = round(min(max(v, lo[n]), hi[n]), 6)
            path = os.path.join(prof_dir, "gen%02d_cand%02d.json" % (gen, k))
            write_profile(path, "CEM gen%d cand%d" % (gen, k), params,
                          "CEM candidate, generation %d" % gen)
            ok, out = lint(path)
            if not ok:
                print("  cand%02d REJECTED by linter before spending any games:\n%s" % (k, out))
                continue
            pop.append({"k": k, "params": params, "profile": path})

        # --- race: everyone gets a cheap look --------------------------------
        # Every candidate in a generation is raced on the SAME seeds. Because the
        # AI's RNG is seeded, that makes the comparison BETWEEN candidates paired
        # too, not just each candidate against the baseline — the ranking stops
        # being polluted by which seeds a candidate happened to draw. Seeds change
        # between generations so the search cannot overfit one seed set.
        race_seed_base = seed_base
        for c in pop:
            res = evaluate(c["profile"], args.fixture, season, args.race_pairs,
                           race_seed_base, args.lanes, args.max_seconds, args.difficulty)
            c["race"] = res
            c["E"] = res.get("E", {}).get("mean")
            c["verdict"] = res.get("verdict")
            print("  race cand%02d: E=%+7s  (%s)" % (c["k"], c["E"], c["verdict"]))

        rated = [c for c in pop if c["E"] is not None]
        if not rated:
            print("  no candidate produced a usable measurement this generation")
            continue
        rated.sort(key=lambda c: -c["E"])
        survivors = rated[: max(args.elite, len(rated) // 2)]

        # --- survivors get a harder look -------------------------------------
        # Fresh seeds, shared across survivors: re-using the race seeds would
        # reward whichever candidate got lucky on them (the winner's curse), and
        # a second look on the same games is not a second look at all.
        seed_base = race_seed_base + args.race_pairs + 20
        final_seed_base = seed_base
        for c in survivors:
            res = evaluate(c["profile"], args.fixture, season, args.final_pairs,
                           final_seed_base, args.lanes, args.max_seconds, args.difficulty)
            c["final"] = res
            fe = res.get("E", {}).get("mean")
            if fe is not None:
                c["E"] = fe
                c["verdict"] = res.get("verdict")
            print("  final cand%02d: E=%+7s se=%-6s (%s)"
                  % (c["k"], c["E"], res.get("E", {}).get("se"), c["verdict"]))

        survivors.sort(key=lambda c: -c["E"])
        elite = survivors[: args.elite]
        if elite and (best["E"] is None or elite[0]["E"] > best["E"]):
            best = {"E": elite[0]["E"], "params": elite[0]["params"],
                    "profile": elite[0]["profile"], "verdict": elite[0]["verdict"]}
            print("  * new best: E = %+.2f VP" % best["E"])

        # --- refit the distribution to the elite ------------------------------
        for n in names:
            vals = [c["params"][n] for c in elite]
            if len(vals) >= 2:
                mu[n] = sum(vals) / len(vals)
                var = sum((v - mu[n]) ** 2 for v in vals) / (len(vals) - 1)
                # floor sigma so the search cannot collapse onto noise
                sigma[n] = max(math.sqrt(var), abs(defaults[n]) * 0.05, 1e-3)
            elif vals:
                mu[n] = vals[0]

        seed_base = final_seed_base + args.final_pairs + 20
        history.append({"generation": gen,
                        "mu": {n: round(mu[n], 4) for n in names},
                        "sigma": {n: round(sigma[n], 4) for n in names},
                        "population": [{"k": c["k"], "E": c["E"], "verdict": c["verdict"],
                                        "params": c["params"]} for c in rated],
                        "best_so_far": best["E"]})
        with open(os.path.join(season, "cem_state.json"), "w") as fh:
            json.dump({"schema": "wh40k_cem_campaign", "dims": names,
                       "defaults": defaults, "args": vars(args),
                       "history": history, "best": best,
                       "wall_seconds": round(time.time() - t0, 1)}, fh, indent=2)

    # ---- write the winner as a shippable profile ---------------------------
    if best["params"]:
        final = os.path.join(season, "cem_best.json")
        diff = {n: (defaults[n], best["params"][n]) for n in names
                if abs(best["params"][n] - defaults[n]) > 1e-9}
        write_profile(final, "CEM best (E = %+.2f VP)" % best["E"], best["params"],
                      "Best CEM candidate. Diff vs defaults: " +
                      "; ".join("%s %g -> %g" % (n, a, b) for n, (a, b) in sorted(diff.items())))
        print("\n" + "=" * 78)
        print("BEST CANDIDATE  E = %+.2f VP/game  (%s)" % (best["E"], best["verdict"]))
        print("=" * 78)
        for n, (a, b) in sorted(diff.items(), key=lambda kv: -abs(kv[1][1] - kv[1][0])):
            print("  %-36s %8g -> %-8g  (%+.0f%%)" % (n, a, b, 100.0 * (b - a) / a if a else 0))
        print("\n  profile: %s" % final)
        print("  This is a CANDIDATE, not an accepted change. It still has to clear")
        print("  the gates: both mirrors, the windowed scenario suite, stall rate and")
        print("  action-mix guardrails. Run tools/ai_lab/gate_candidate.py.")
    else:
        print("\nNo candidate beat the baseline in this campaign.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
