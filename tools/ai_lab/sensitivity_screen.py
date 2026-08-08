#!/usr/bin/env python3
"""M3 — which constants actually move the margin?

Searching all 126 tunable parameters is wasteful: most will not shift the
outcome at all, and every candidate costs games. A one-at-a-time screen buys a
ranking cheaply, and the ranking chooses the dimensions the M4 optimiser
actually searches.

Method. For each parameter, build two profiles — default x (1+delta) and
default x (1-delta) — and evaluate each through the paired, side-swapped
driver against the shipped defaults. Because the AI's RNG is seeded, a pair
shares dice, deck AND noise draws, so the pair difference isolates the
parameter and nothing else. Rank by the larger |E| of the two directions.

Two properties worth stating plainly:

  * A parameter that produces E = 0 with zero variance across every paired
    seed changed no DECISION at this delta — every game replayed identically.
    That is not a weak effect, it is no effect, and it is reported as `no_op`
    rather than as a small number. Note what it does NOT prove: the parameter
    may well be read, and simply never move an argmax (it scales a term that
    is dominated, or the unit had only one option). "Unread" and "read but
    never decisive" are indistinguishable from the outcome alone.
  * The screen ranks INFLUENCE, not benefit. A parameter with a large |E| is
    worth searching over; the sign here is one noisy sample and must not be
    read as "set it this way".

Usage:
    python3 tools/ai_lab/sensitivity_screen.py --season bench_data/screen1
    python3 tools/ai_lab/sensitivity_screen.py --params A,B,C --pairs 6
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

from params_manifest import build_manifest  # noqa: E402

# Default screen set: the coefficients that decide games — objective
# assignment (which drives ~2/3 of all recorded decisions), plus charge and
# fight target selection, plus the highest-traffic pre-existing weights.
DEFAULT_PARAMS = [
    # objective assignment / movement
    "MOVE_TURNS_AWAY_PENALTY", "MOVE_STAY_BONUS_LATE", "MOVE_STAY_BONUS_SCORING",
    "MOVE_REACHABLE_BONUS", "MOVE_UNREACHABLE_EARLY_PENALTY", "MOVE_HORDE_BONUS_LARGE",
    "WEIGHT_CONTESTED_OBJ", "WEIGHT_UNCONTROLLED_OBJ", "WEIGHT_VP_PER_POINT",
    "WEIGHT_OC_EFFICIENCY", "WEIGHT_ALREADY_HELD_OBJ",
    # charge
    "CHARGE_MELEE_DAMAGE_WEIGHT", "CHARGE_BELOW_HALF_BONUS", "CHARGE_TIE_UP_SHOOTER_BONUS",
    # fight
    "FIGHT_MELEE_DAMAGE_WEIGHT", "FIGHT_CAN_WIPE_BONUS", "FIGHT_CHARACTER_BONUS",
    # shooting
    "OVERKILL_TOLERANCE", "KILL_BONUS_MULTIPLIER",
    # tempo / strategy
    "STRATEGY_LATE_OBJECTIVE", "STRATEGY_EARLY_OBJECTIVE",
]


def write_profile(path, name, params, description):
    with open(path, "w") as fh:
        json.dump({"format": "wh40k_ai_profile", "version": 1,
                   "profile_name": name, "description": description,
                   "parameters": params, "rules": []}, fh, indent=2)


def evaluate(profile, fixture, season, pairs, seed_base, lanes, max_seconds, difficulty):
    """One paired campaign. Returns the driver's own summary dict."""
    cmd = [sys.executable, os.path.join(HERE, "run_paired.py"),
           "--candidate", profile, "--fixture", fixture, "--season", season,
           "--seed-base", str(seed_base), "--min-pairs", str(pairs),
           "--max-pairs", str(pairs), "--batch", str(pairs),
           "--lanes", str(lanes), "--max-seconds", str(max_seconds),
           "--difficulty", str(difficulty), "--quiet"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    for line in reversed(r.stdout.strip().splitlines()):
        try:
            return json.loads(line)
        except ValueError:
            continue
    return {"verdict": "error", "E": {"n": 0}, "stderr": r.stderr[-400:]}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--season", required=True)
    ap.add_argument("--fixture", default="mirror_custodes_2000_postdeploy",
                    help="Custodes by default: ~48 s/game against ~487 s for the Ork "
                         "mirror, so a screen there costs about a tenth as much")
    ap.add_argument("--params", default="", help="comma-separated; default: the built-in set")
    ap.add_argument("--delta", type=float, default=0.30)
    ap.add_argument("--pairs", type=int, default=5, help="paired seeds per direction")
    ap.add_argument("--seed-base", type=int, default=20000)
    ap.add_argument("--lanes", type=int, default=3)
    ap.add_argument("--difficulty", type=int, default=2)
    ap.add_argument("--max-seconds", type=float, default=400.0)
    args = ap.parse_args(argv)

    manifest = build_manifest()["parameters"]
    names = [p.strip() for p in args.params.split(",") if p.strip()] or DEFAULT_PARAMS
    names = [n for n in names if n in manifest and manifest[n]["default"] is not None]

    season = os.path.abspath(args.season)
    prof_dir = os.path.join(season, "_profiles")
    os.makedirs(prof_dir, exist_ok=True)

    print("=" * 78)
    print("SENSITIVITY SCREEN — %d parameters x 2 directions (+/-%.0f%%), %d pairs each"
          % (len(names), args.delta * 100, args.pairs))
    print("  fixture=%s  => %d games total" % (args.fixture, len(names) * 2 * args.pairs * 2))
    print("=" * 78)

    results = []
    seed_base = args.seed_base
    t0 = time.time()
    for i, name in enumerate(names, 1):
        base = float(manifest[name]["default"])
        row = {"param": name, "default": base, "directions": {}}
        for label, factor in (("up", 1.0 + args.delta), ("down", 1.0 - args.delta)):
            value = round(base * factor, 6)
            path = os.path.join(prof_dir, "%s_%s.json" % (name, label))
            write_profile(path, "screen %s %s" % (name, label), {name: value},
                          "M3 sensitivity screen: %s = %g (default %g)" % (name, value, base))
            # Its own season subdirectory as well as the candidate filter in
            # run_paired: two independent defences against one campaign's games
            # being counted in another's arithmetic.
            sub = os.path.join(season, "%s_%s" % (name, label))
            res = evaluate(path, args.fixture, sub, args.pairs, seed_base,
                           args.lanes, args.max_seconds, args.difficulty)
            seed_base += args.pairs + 10
            e = res.get("E", {})
            row["directions"][label] = {"value": value, "verdict": res.get("verdict"),
                                        "E": e.get("mean"), "se": e.get("se"), "n": e.get("n")}
            print("  [%2d/%2d] %-34s %-4s %-8s E=%+7s se=%-6s"
                  % (i, len(names), name, label, res.get("verdict"),
                     e.get("mean"), e.get("se")))
        eff = [abs(d["E"]) for d in row["directions"].values() if d["E"] is not None]
        row["influence"] = max(eff) if eff else 0.0
        row["no_op"] = all(d["verdict"] == "no_op" for d in row["directions"].values())
        results.append(row)
        # Checkpoint after every parameter. A full screen is hours of games and
        # writing only at the end means an interruption throws all of it away.
        with open(os.path.join(season, "screen_results.json"), "w") as fh:
            json.dump({"fixture": args.fixture, "delta": args.delta, "pairs": args.pairs,
                       "complete": False, "wall_seconds": round(time.time() - t0, 1),
                       "results": sorted(results, key=lambda r: -r["influence"])}, fh, indent=2)

    results.sort(key=lambda r: -r["influence"])
    out = os.path.join(season, "screen_results.json")
    with open(out, "w") as fh:
        json.dump({"fixture": args.fixture, "delta": args.delta, "pairs": args.pairs,
                   "complete": True,
                   "wall_seconds": round(time.time() - t0, 1), "results": results}, fh, indent=2)

    print("\n" + "=" * 78)
    print("RANKED INFLUENCE  (max |E| across the two directions)")
    print("=" * 78)
    print("  %-36s %-9s %-9s %s" % ("parameter", "default", "|E| max", "note"))
    for r in results:
        note = "no decision changed at +/-%.0f%%" % (args.delta * 100) if r["no_op"] else ""
        print("  %-36s %-9g %-9.2f %s" % (r["param"], r["default"], r["influence"], note))

    movers = [r for r in results if not r["no_op"] and r["influence"] >= 2.0]
    print("\n  %d parameter(s) move the margin by >= 2 VP; %d are no-ops on this fixture."
          % (len(movers), sum(1 for r in results if r["no_op"])))
    print("  Kill criterion from the design document: if fewer than 5 parameters clear")
    print("  2 VP, use coordinate descent instead of CEM. Currently: %s"
          % ("CEM" if len(movers) >= 5 else "COORDINATE DESCENT"))
    print("  results: %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
