#!/usr/bin/env python3
"""Counterfactual rollouts: what is one AI decision worth?

From a saved position (an LLM-critic case: tools/llm_critic writes
<id>.json + <id>.w40ksave under user://llm_critic/<run>/), play the AI's own
choice (branch A) and a proposed alternative (branch B: a one-shot forced
decision, AIDecisionMaker ROLLOUT override) forward to a fixed horizon over
many seeds, and compare what the deciding player gains.

  value    = (VP gained by the decider) - (VP gained by the opponent), from the
             decision point to the horizon
  material = points the opponent lost - points the decider lost (a unit's
             points x the share of its wounds gone), same window
  effect   = mean over seeds of [B - A], with se and a 95% range

Both branches of a seed load the same save and use the same seed, so they are
identical up to the forced decision. --horizon N stops the game the moment
battle round (decision round + N + 1) begins — e.g. a round-2 decision with
--horizon 1 is measured after round 3, so round 3's Command-phase scoring of
the positions left by round 2 is included. --horizon 0 plays to the end.

Overrides (JSON list; "round" and "player" default to the case's):
  {"kind": "move",   "unit": "U_X", "objective": "obj_center", "mode": "move"|"advance"|"hold"}
  {"kind": "shoot",  "unit": "U_X", "target": "U_Y"}
  {"kind": "charge", "unit": "U_X", "targets": ["U_Y"]}      ([] = do not charge)

Usage:
  python3 tools/ai_lab/rollout.py run --case <case.json> --alt '<json list>' --seeds 20 [--horizon 1] [--lanes 4]
  python3 tools/ai_lab/rollout.py run --case <case.json> --alt none --seeds 6    (A only: noise floor of one branch)
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import os
import re
import shutil
import statistics
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
PROJECT = os.path.join(REPO, "40k")
GODOT_BIN = "/root/.cache/godot/Godot_v4.4.1-stable_linux.x86_64"
sys.path.insert(0, HERE)
from run_lanes import userdata_dir  # noqa: E402

_lock = threading.Lock()


def say(msg: str) -> None:
    with _lock:
        print(msg, flush=True)


def godot_cmd() -> list:
    if os.path.exists(GODOT_BIN):
        return [GODOT_BIN]
    return ["godot"]


def stats(vals: list) -> dict:
    n = len(vals)
    if n == 0:
        return {"n": 0}
    mean = statistics.fmean(vals)
    sd = statistics.stdev(vals) if n > 1 else float("nan")
    se = sd / math.sqrt(n) if n > 1 else float("nan")
    return {"n": n, "mean": round(mean, 3), "sd": None if n < 2 else round(sd, 3),
            "se": None if n < 2 else round(se, 3),
            "ci95": None if n < 2 else [round(mean - 1.96 * se, 2), round(mean + 1.96 * se, 2)]}


def load_case(path: str) -> dict:
    case = json.load(open(path))
    case["_dir"] = os.path.dirname(os.path.abspath(path))
    return case


def install_fixture(case: dict, ud: str) -> str:
    """Copy the case's save (+ .meta) into user://saves/ under a rollout name."""
    name = "ro_" + str(case["id"])
    src = os.path.join(case["_dir"], case["save_file"])
    dst_dir = os.path.join(ud, "saves")
    os.makedirs(dst_dir, exist_ok=True)
    shutil.copy(src, os.path.join(dst_dir, name + ".w40ksave"))
    meta = os.path.splitext(src)[0] + ".meta"
    if os.path.exists(meta):
        shutil.copy(meta, os.path.join(dst_dir, name + ".meta"))
    return name


def run_branch(fixture: str, branch: str, seed: int, override_path: str, stop_round: int,
               out_dir_rel: str, ud: str, max_seconds: float, keep: bool) -> dict:
    out_rel = "%s/%s_%d.json" % (out_dir_rel, branch, seed)
    result_path = os.path.join(ud, out_rel)
    record_path = result_path.replace(".json", ".record.json")
    cmd = godot_cmd() + ["--headless", "--quiet", "--path", PROJECT, "--", "--ai-benchmark",
                         "--bench-fixture=%s" % fixture, "--bench-seed=%d" % seed,
                         "--bench-difficulty=3", "--bench-time-scale=6",
                         "--bench-max-seconds=%g" % max_seconds, "--bench-out=%s" % out_rel,
                         "--bench-arm=ROLLOUT_%s" % branch]
    if stop_round > 0:
        cmd.append("--bench-stop-round=%d" % stop_round)
    if override_path:
        cmd.append("--bench-override=%s" % override_path)
    t0 = time.time()
    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=max_seconds + 180)
    except subprocess.TimeoutExpired:
        return {"branch": branch, "seed": seed, "status": "hard_timeout"}
    out = {"branch": branch, "seed": seed, "status": "missing", "wall": round(time.time() - t0, 1)}
    if os.path.exists(result_path):
        out.update(json.load(open(result_path)))
        out["wall"] = round(time.time() - t0, 1)
    if os.path.exists(record_path):
        rec = json.load(open(record_path))
        out["_decisions"] = rec.get("decisions", [])
        if not keep:
            os.remove(record_path)
    return out


def value_of(res: dict, me: int) -> dict:
    """VP and material gained by `me` relative to the opponent since the start."""
    op = 3 - me
    vs, ve = res.get("vp_start", {}), res.get("vp", {})

    def vp(d, p):
        return float(d.get("player%d" % p, {}).get("total", 0))
    ms, me_ = res.get("material_start", {}), res.get("material_end", {})

    def lost(d, p):
        return float(d.get(str(p), 0))
    value = (vp(ve, me) - vp(vs, me)) - (vp(ve, op) - vp(vs, op))
    material = (lost(me_, op) - lost(ms, op)) - (lost(me_, me) - lost(ms, me))
    return {"value": value, "material": material}


def decision_key(desc: str) -> str:
    """The decisive part of an action text: who does what to whom, without the
    numbers after it ("X shoots at Y \u2014 expected 0.9 dmg ..." -> "X shoots at Y").
    The old check compared the first 60 characters, which can stop before the
    target name, so "shoots at Gamma" and "shoots at Alpha" matched."""
    cut = len(desc)
    for sep in (" \u2014 ", " (", ";"):
        i = desc.find(sep)
        if 0 < i < cut:
            cut = i
    return desc[:cut].strip()


ACTOR_RE = re.compile(r"^(.*?) (shoots at|moves|advances|holds|stays|declares|arrives|falls back|remains)\b")


def drift_check(res: dict, case: dict) -> dict:
    """Did branch A make the decision the critic reviewed? Compares the decisive
    part of the case's suggestion with the decider's actions in that round and
    phase. Also reports what A's acting unit did instead ("a_did"): when A
    already makes the alternative, B equals A and the job measures nothing."""
    want = decision_key(str(case.get("suggestion", "")))
    m = ACTOR_RE.match(want)
    actor = m.group(1) if m else ""
    phase = str(case.get("phase_name", "")).lower()
    seen = []
    a_did = ""
    for d in res.get("_decisions", []):
        if int(d.get("player", 0)) != int(case.get("player", 0)) or int(d.get("round", 0)) != int(case.get("round", 0)):
            continue
        if phase and str(d.get("phase_name", "")).lower() != phase:
            continue
        for a in d.get("actions", []):
            desc = str(a.get("description", ""))
            seen.append(desc[:120])
            if actor and not a_did and desc.startswith(actor + " "):
                a_did = desc[:160]
            if want and decision_key(desc) == want:
                return {"reproduced": True, "matched": desc[:160], "a_did": desc[:160]}
    return {"reproduced": False, "first_actions": seen[:4], "a_did": a_did}


def cmd_run(args) -> int:
    ud = userdata_dir()
    case = load_case(args.case)
    me = int(case.get("player", 1))
    rnd = int(case.get("round", 1))
    fixture = install_fixture(case, ud)
    stop_round = rnd + args.horizon if args.horizon > 0 else 0
    tag = args.tag or ("%s_h%d" % (case["id"], args.horizon))
    out_dir_rel = "test_results/rollout/%s" % tag
    os.makedirs(os.path.join(ud, out_dir_rel), exist_ok=True)

    override_path = ""
    if args.alt and args.alt != "none":
        alts = json.loads(open(args.alt).read() if os.path.exists(args.alt) else args.alt)
        for ov in alts:
            ov.setdefault("round", rnd)
            ov.setdefault("player", me)
        override_path = os.path.join(ud, out_dir_rel, "override.json")
        json.dump(alts, open(override_path, "w"))

    seeds = list(range(args.seed_base + 1, args.seed_base + args.seeds + 1))
    jobs = [("A", s, "") for s in seeds]
    if override_path:
        jobs += [("B", s, override_path) for s in seeds]
    say("rollout %s: %s, decider P%d round %d, horizon %s, %d seeds, %d games" % (
        tag, case.get("suggestion", "")[:80], me, rnd, ("end of round %d" % stop_round) if stop_round else "full game",
        len(seeds), len(jobs)))
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.lanes) as pool:
        futs = {pool.submit(run_branch, fixture, b, s, ov, stop_round, out_dir_rel, ud,
                            args.max_seconds, args.keep): (b, s) for b, s, ov in jobs}
        for f in concurrent.futures.as_completed(futs):
            r = f.result()
            results[(r["branch"], r["seed"])] = r
            v = value_of(r, me) if r.get("status") == "completed" else {}
            say("  %s seed %d: %s value %s material %s (%ss)" % (r["branch"], r["seed"], r.get("status"),
                v.get("value"), v.get("material"), r.get("wall")))

    summary = {"case": case["id"], "suggestion": case.get("suggestion", ""), "decider": me, "round": rnd,
               "horizon": args.horizon, "stop_round": stop_round, "seeds": seeds,
               "override": json.load(open(override_path)) if override_path else None}
    a_vals = {s: value_of(results[("A", s)], me) for s in seeds
              if results.get(("A", s), {}).get("status") == "completed"}
    summary["A"] = {"value": stats([v["value"] for v in a_vals.values()]),
                    "material": stats([v["material"] for v in a_vals.values()])}
    first_a = next((results[("A", s)] for s in seeds if ("A", s) in results), {})
    summary["drift"] = drift_check(first_a, case)
    if override_path:
        b_vals = {s: value_of(results[("B", s)], me) for s in seeds
                  if results.get(("B", s), {}).get("status") == "completed"}
        paired = [s for s in seeds if s in a_vals and s in b_vals]
        summary["B"] = {"value": stats([b_vals[s]["value"] for s in paired]),
                        "material": stats([b_vals[s]["material"] for s in paired])}
        summary["effect_value"] = stats([b_vals[s]["value"] - a_vals[s]["value"] for s in paired])
        summary["effect_material"] = stats([b_vals[s]["material"] - a_vals[s]["material"] for s in paired])
        # applied = the forced decision was taken; "noop" = the override fired
        # but was not applicable (e.g. no weapon can target that unit) and the
        # AI's own choice was kept, so B equals A and the job measures nothing.
        summary["override_applied"] = [all(bool(o.get("used", False)) and not o.get("noop", False)
                                           for o in results[("B", s)].get("rollout_overrides", []))
                                       for s in paired]
        summary["identical_pairs"] = sum(1 for s in paired if b_vals[s] == a_vals[s])
        summary["per_seed"] = [{"seed": s, "A": a_vals[s], "B": b_vals[s]} for s in paired]
    else:
        summary["per_seed"] = [{"seed": s, "A": a_vals[s]} for s in seeds if s in a_vals]
    summary["walls"] = stats([r.get("wall", 0) for r in results.values() if r.get("wall")])
    out_json = args.out or os.path.join(ud, out_dir_rel, "summary.json")
    json.dump(summary, open(out_json, "w"), indent=1)
    say(json.dumps({k: summary[k] for k in summary if k not in ("per_seed", "seeds")}, indent=None))
    say("summary: %s" % out_json)
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--case", required=True, help="critic case JSON (next to its .w40ksave)")
    r.add_argument("--alt", default="none", help="override JSON list (inline or file), or 'none'")
    r.add_argument("--seeds", type=int, default=20)
    r.add_argument("--seed-base", type=int, default=5000)
    r.add_argument("--horizon", type=int, default=1, help="rounds after the decision round; 0 = full game")
    r.add_argument("--lanes", type=int, default=4)
    r.add_argument("--max-seconds", type=float, default=1500)
    r.add_argument("--tag", default="")
    r.add_argument("--out", default="")
    r.add_argument("--keep", action="store_true", help="keep the per-game records")
    args = ap.parse_args(argv)
    return cmd_run(args)


if __name__ == "__main__":
    sys.exit(main())
