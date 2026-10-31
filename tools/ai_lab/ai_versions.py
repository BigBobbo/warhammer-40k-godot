#!/usr/bin/env python3
"""Old-vs-new AI head to head: AIDecisionMaker version A against version B.

run_paired.py compares PROFILES (parameter files) on the current code. This
tool compares CODE: each seat plays with its own copy of AIDecisionMaker.gd,
taken from a git ref. Everything else (rules, phases, dice) is the current
build, so the comparison isolates the decision maker.

    extract  git show <ref>:40k/scripts/AIDecisionMaker.gd
             -> 40k/scripts/ai_versions/<name>/AIDecisionMaker.gd
             (class_name removed, so it is a separate script with its own
             static caches and RNG; the dir is gitignored)
    run      seed-paired, side-swapped arms, same design as run_paired.py:
               arm <tag>_M1: P1 = base, P2 = cand  ->  F + E
               arm <tag>_M2: P1 = cand, P2 = base  ->  F - E
               E = (M1 - M2) / 2  (margin = VP(P2) - VP(P1); E > 0: cand better)

Usage:
    python3 tools/ai_lab/ai_versions.py extract V0=0633cc1 V3=HEAD
    python3 tools/ai_lab/ai_versions.py run --base V0 --cand V3 \\
        --season bench_data/ai_versions --seed-base 9100 --pairs 6
    python3 tools/ai_lab/ai_versions.py report --season bench_data/ai_versions
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import run_lanes  # noqa: E402
from build_index import find_records, load_record, SCHEMA, _int, _num  # noqa: E402
from run_paired import Args, stats  # noqa: E402

VERSIONS_DIR = os.path.join(REPO, "40k", "scripts", "ai_versions")
SRC = "40k/scripts/AIDecisionMaker.gd"


def res_path(name: str) -> str:
    return "res://scripts/ai_versions/%s/AIDecisionMaker.gd" % name


def extract(specs: list[str]) -> None:
    for spec in specs:
        name, ref = spec.split("=", 1)
        src = subprocess.check_output(["git", "-C", REPO, "show", "%s:%s" % (ref, SRC)], text=True)
        src, n = re.subn(r"^class_name AIDecisionMaker\s*$", "# class_name removed by ai_versions.py", src,
                         count=1, flags=re.M)
        if n != 1:
            raise SystemExit("%s: class_name line not found" % ref)
        if re.search(r"\bAIDecisionMaker\.", src):
            # A self reference would call the CURRENT decision maker, not this copy.
            print("WARNING %s: copy references AIDecisionMaker.* by name" % name)
        d = os.path.join(VERSIONS_DIR, name)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "AIDecisionMaker.gd"), "w") as f:
            f.write(src)
        sha = subprocess.check_output(["git", "-C", REPO, "rev-parse", "--short", ref], text=True).strip()
        with open(os.path.join(d, "VERSION.json"), "w") as f:
            json.dump({"name": name, "ref": ref, "sha": sha}, f)
        print("extracted %s = %s (%s)" % (name, ref, sha))


def play(seeds, args, tag, arm, p1_ai, p2_ai, stamp, sha, p1_profile="", p2_profile=""):
    import concurrent.futures
    a = Args(fixture=args.fixture, arm="%s_%s" % (tag, arm), p1_profile=p1_profile, p2_profile=p2_profile,
             p1_plan="", p2_plan="", p1_ai=p1_ai, p2_ai=p2_ai, dispositions=args.dispositions, bench_11e=args.rules11e,
             difficulty=args.difficulty, time_scale=args.time_scale, max_seconds=args.max_seconds,
             lanes=args.lanes, seeds="", season=args.season, skip_gate=True)
    ud = run_lanes.userdata_dir()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.lanes) as pool:
        list(pool.map(lambda s: run_lanes.run_one(s, a, stamp, ud, args.season, sha), seeds))


def margins(season: str, arm: str) -> dict:
    out = {}
    for p in find_records(season):
        try:
            rec = load_record(p)
        except (OSError, ValueError):
            continue
        if rec.get("schema") != SCHEMA:
            continue
        prov, o = rec.get("provenance") or {}, rec.get("outcome") or {}
        if prov.get("arm") == arm and o.get("status") == "completed":
            out[_int(prov.get("seed"), -1)] = _num(o.get("vp_diff_p2_minus_p1"), 0.0)
    return out


def summarise(season: str, tag: str) -> dict:
    m1, m2 = margins(season, tag + "_M1"), margins(season, tag + "_M2")
    paired = sorted(set(m1) & set(m2))
    eff = [(m1[s] - m2[s]) / 2.0 for s in paired]
    # Game wins for the candidate: M1 cand is P2 (margin > 0), M2 cand is P1 (margin < 0).
    w = l = d = 0
    for s in paired:
        for m in (m1[s], -m2[s]):
            if m > 0:
                w += 1
            elif m < 0:
                l += 1
            else:
                d += 1
    return {"tag": tag, "pairs": len(paired), "E": stats(eff), "wins": w, "losses": l, "draws": d,
            "per_seed": [{"seed": s, "M1": m1[s], "M2": m2[s], "E": (m1[s] - m2[s]) / 2.0} for s in paired]}


def cmd_run(args) -> int:
    args.season = os.path.abspath(args.season)
    os.makedirs(args.season, exist_ok=True)
    for v in (args.base, args.cand):
        if v != "HEAD" and not os.path.exists(os.path.join(VERSIONS_DIR, v, "AIDecisionMaker.gd")):
            raise SystemExit("version %s not extracted" % v)
    base = res_path(args.base) if args.base != "HEAD" else ""
    cand = res_path(args.cand) if args.cand != "HEAD" else ""
    tag = args.tag or "%s_vs_%s" % (args.cand, args.base)
    sha, stamp = run_lanes.git_sha(), time.strftime("%Y%m%d_%H%M%S")
    seeds = list(range(args.seed_base + 1, args.seed_base + args.pairs + 1))
    print("%s: seeds %s" % (tag, seeds), flush=True)
    # --cand-profile: parameter overrides for the candidate seat (ablation
    # toggles). Profiles load into the current AIDecisionMaker only, so the
    # candidate must be HEAD.
    prof = os.path.abspath(args.cand_profile) if args.cand_profile else ""
    if prof and args.cand != "HEAD":
        raise SystemExit("--cand-profile needs --cand HEAD")
    play(seeds, args, tag, "M1", base, cand, stamp, sha, p2_profile=prof)
    play(seeds, args, tag, "M2", cand, base, stamp, sha, p1_profile=prof)
    s = summarise(args.season, tag)
    print(json.dumps({k: v for k, v in s.items() if k != "per_seed"}), flush=True)
    with open(os.path.join(args.season, "%s.summary.json" % tag), "w") as f:
        json.dump(s, f, indent=1)
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("extract")
    e.add_argument("specs", nargs="+", help="NAME=gitref")
    r = sub.add_parser("run")
    r.add_argument("--base", required=True, help="version name, or HEAD for the current code")
    r.add_argument("--cand", required=True)
    r.add_argument("--tag", default="")
    r.add_argument("--cand-profile", default="", help="profile JSON for the HEAD candidate seat")
    r.add_argument("--season", required=True)
    r.add_argument("--seed-base", type=int, default=9100)
    r.add_argument("--pairs", type=int, default=6)
    r.add_argument("--fixture", default="mirror_custodes_2000_postdeploy")
    r.add_argument("--rules11e", action="store_true",
                   help="11e GDM primary cards (rotating by seed) + 11e secondary deck; "
                        "the fixture alone scores legacy Take and Hold with the 10e deck")
    r.add_argument("--dispositions", default="",
                   help="e.g. take_and_hold,take_and_hold: play the 11e primary cards "
                        "(the fixture save has none, so it scores legacy Take and Hold)")
    r.add_argument("--lanes", type=int, default=3)
    r.add_argument("--difficulty", type=int, default=3, help="3 = Competitive")
    r.add_argument("--time-scale", type=float, default=6.0)
    r.add_argument("--max-seconds", type=float, default=900.0)
    p = sub.add_parser("report")
    p.add_argument("--season", required=True)
    args = ap.parse_args(argv)
    if args.cmd == "extract":
        extract(args.specs)
        return 0
    if args.cmd == "run":
        return cmd_run(args)
    for fn in sorted(os.listdir(args.season)):
        if fn.endswith(".summary.json"):
            s = json.load(open(os.path.join(args.season, fn)))
            E = s["E"]
            print("%-14s pairs %2d  E %+6.2f VP  se %s  CI %s  cand W/L/D %d/%d/%d" % (
                s["tag"], s["pairs"], E.get("mean", float("nan")), E.get("se"), E.get("ci95"),
                s["wins"], s["losses"], s["draws"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
