#!/usr/bin/env python3
"""Run one benchmark arm across concurrent lanes, into a season directory.

`run_ai_benchmark.sh` plays games strictly one at a time, so a 20-game arm
takes 20 x ~6 min = 2 hours of wall clock on a 4-core box that could be
running three at once. This is the concurrency primitive the M2 paired A/B
driver needs: it owns "play N games of ONE arm and collect them", and knows
nothing about pairing, side-swapping or stopping rules — those compose on top.

What it guarantees that a shell `for` loop does not:
  * the M0 fixture gate is FATAL here, not advisory. A campaign that runs on
    an unvalidated fixture confidently learns garbage.
  * every game lands in the season directory as a gzipped record, so the run
    is directly consumable by build_index.py.
  * stdout logs (41-51 MB each) are kept only for games that did not complete.
  * already-finished seeds are skipped, so an interrupted arm resumes.

Usage:
    python3 tools/ai_lab/run_lanes.py --fixture mirror_orks_postdeploy \\
        --seeds 7001-7020 --arm AA --lanes 3 --season bench_data/season_aa

An A/A arm is simply this with no profiles on either side (or the same profile
on both): identical policy, both players, so the mean margin isolates the
fixture's structural bias F — first turn plus board side — and nothing else.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import gzip
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
PROJECT = os.path.join(REPO, "40k")

_print_lock = threading.Lock()


def say(msg: str) -> None:
    with _print_lock:
        print(msg, flush=True)


def userdata_dir() -> str:
    if platform.system() == "Darwin":
        return os.path.expanduser("~/Library/Application Support/Godot/app_userdata/40k")
    return os.path.expanduser("~/.local/share/godot/app_userdata/40k")


def parse_seeds(spec: str) -> list[int]:
    out: list[int] = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            lo, hi = part.split("-", 1)
            out.extend(range(int(lo), int(hi) + 1))
        else:
            out.append(int(part))
    return out


def git_sha() -> str:
    try:
        sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO,
                             capture_output=True, text=True, check=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain"], cwd=REPO,
                               capture_output=True, text=True).stdout.strip()
        return sha + ("-dirty" if dirty else "")
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def gate_fixture(fixture: str) -> None:
    """M0: refuse to spend hours of compute on a broken environment."""
    r = subprocess.run([sys.executable, os.path.join(HERE, "fixture_check.py"), fixture],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout)
        raise SystemExit(
            "FIXTURE CHECK FAILED for %r — refusing to run a campaign on it.\n"
            "A learning loop pointed at a broken environment learns garbage, fast."
            % fixture)
    say("fixture gate: %s PASS" % fixture)


def run_one(seed: int, args, stamp: str, ud: str, season: str, sha: str) -> dict:
    tag = "%s_%s_%d" % (stamp, args.arm, seed)
    out_rel = "test_results/bench/%s.json" % tag
    result_path = os.path.join(ud, out_rel)
    record_path = result_path.replace(".json", ".record.json")
    season_record = os.path.join(season, "%s.record.json.gz" % tag)

    # Resume on (arm, seed), not on the exact filename. The tag carries a
    # per-invocation timestamp, so a resumed campaign used to replay every game
    # it had already paid for — which matters a lot here, because a suspended
    # container kills the driver and losing an hour of games to a restart is
    # worse than any amount of tidiness.
    existing = None
    if os.path.exists(season_record):
        existing = season_record
    else:
        suffix = "_%s_%d.record.json.gz" % (args.arm, seed)
        for name in sorted(os.listdir(season)) if os.path.isdir(season) else []:
            if name.endswith(suffix):
                existing = os.path.join(season, name)
                break
    if existing:
        say("  [seed %d] already collected — skipping" % seed)
        try:
            with gzip.open(existing, "rt") as fh:
                return {"seed": seed, **(json.load(fh).get("outcome") or {}), "skipped": True}
        except OSError:
            pass

    cmd = ["godot", "--headless", "--path", PROJECT, "--", "--ai-benchmark",
           "--bench-fixture=%s" % args.fixture, "--bench-seed=%d" % seed,
           "--bench-out=%s" % out_rel, "--bench-difficulty=%d" % args.difficulty,
           "--bench-time-scale=%g" % args.time_scale,
           "--bench-max-seconds=%g" % args.max_seconds,
           "--bench-git-sha=%s" % sha, "--bench-arm=%s" % args.arm]
    if args.p1_profile:
        cmd.append("--bench-p1-profile=%s" % args.p1_profile)
    if args.p2_profile:
        cmd.append("--bench-p2-profile=%s" % args.p2_profile)

    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/bin") + os.pathsep + env.get("PATH", "")

    log_path = os.path.join(season, "_logs", "%s.log" % tag)
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    t0 = time.time()
    with open(log_path, "w") as log:
        try:
            subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, env=env,
                           timeout=args.max_seconds + 180)
        except subprocess.TimeoutExpired:
            say("  [seed %d] hard timeout — the process outlived its own stall guard" % seed)

    outcome = {"status": "missing", "note": "no result file", "seed": seed}
    if os.path.exists(result_path):
        try:
            with open(result_path) as fh:
                outcome = json.load(fh)
        except ValueError as exc:
            outcome = {"status": "unparseable", "note": str(exc), "seed": seed}

    # Collect the record into the season, gzipped.
    if os.path.exists(record_path):
        with open(record_path, "rb") as src, gzip.open(season_record, "wb") as dst:
            shutil.copyfileobj(src, dst)
        os.remove(record_path)

    # Keep the stdout log only when something went wrong: 41-51 MB per game.
    # NOTE `timeout` != `stalled`: a timeout means the box was too slow (usually
    # oversubscribed lanes) while the game was still progressing. Both are
    # unusable as data, but only `stalled` indicates an AI defect.
    status = outcome.get("status", "missing")
    if status == "completed":
        os.remove(log_path)
    else:
        with open(log_path, "rb") as src, gzip.open(log_path + ".gz", "wb") as dst:
            shutil.copyfileobj(src, dst)
        os.remove(log_path)

    say("  [seed %d] %-9s margin %+4s  rounds %s  actions %s  %.0fs" % (
        seed, status, outcome.get("vp_diff_p2_minus_p1", "?"),
        outcome.get("battle_round", "?"), outcome.get("actions_taken", "?"),
        time.time() - t0))
    outcome["seed"] = seed
    return outcome


def summarise(results: list[dict], args, sha: str) -> dict:
    completed = [r for r in results if r.get("status") == "completed"]
    bad = [r for r in results if r.get("status") != "completed"]
    timeouts = [r for r in results if r.get("status") == "timeout"]
    stalls = [r for r in results if r.get("status") == "stalled"]
    margins = [float(r.get("vp_diff_p2_minus_p1", 0)) for r in completed]

    mean = statistics.fmean(margins) if margins else float("nan")
    sd = statistics.stdev(margins) if len(margins) > 1 else float("nan")
    se = sd / (len(margins) ** 0.5) if len(margins) > 1 else float("nan")

    return {
        "arm": args.arm, "fixture": args.fixture, "git_sha": sha,
        "difficulty": args.difficulty, "time_scale": args.time_scale,
        "p1_profile": args.p1_profile or "", "p2_profile": args.p2_profile or "",
        "games": len(results), "completed": len(completed), "not_completed": len(bad),
        "stalled": len(stalls), "timed_out": len(timeouts),
        "mean_margin_p2_minus_p1": round(mean, 3) if margins else None,
        "sd": round(sd, 3) if len(margins) > 1 else None,
        "se": round(se, 3) if len(margins) > 1 else None,
        "ci95_low": round(mean - 1.96 * se, 2) if len(margins) > 1 else None,
        "ci95_high": round(mean + 1.96 * se, 2) if len(margins) > 1 else None,
        "per_game": [{"seed": r.get("seed"), "status": r.get("status"),
                      "margin": r.get("vp_diff_p2_minus_p1"),
                      "rounds": r.get("battle_round"),
                      "actions": r.get("actions_taken"),
                      "wall_seconds": r.get("wall_seconds"),
                      "note": r.get("note", "")} for r in
                     sorted(results, key=lambda x: x.get("seed", 0))],
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fixture", default="mirror_custodes_2000_postdeploy")
    ap.add_argument("--seeds", default="7001-7010", help="e.g. 7001-7020 or 1,2,3")
    ap.add_argument("--arm", default="AA", help="label recorded in provenance")
    ap.add_argument("--lanes", type=int, default=3,
                    help="concurrent games. Leave a core free: the design doc measured "
                         "6.4-7.8 min/game at 4 contended lanes on 4 cores.")
    ap.add_argument("--difficulty", type=int, default=2, help="2 = Hard (the benchmark default)")
    ap.add_argument("--time-scale", type=float, default=6.0)
    ap.add_argument("--max-seconds", type=float, default=700.0)
    ap.add_argument("--p1-profile", default="")
    ap.add_argument("--p2-profile", default="")
    ap.add_argument("--season", required=True, help="season directory for the records")
    ap.add_argument("--skip-gate", action="store_true",
                    help="skip the M0 fixture check (do not use for a real campaign)")
    args = ap.parse_args(argv)

    seeds = parse_seeds(args.seeds)
    season = os.path.abspath(args.season)
    os.makedirs(season, exist_ok=True)
    ud = userdata_dir()
    sha = git_sha()
    stamp = time.strftime("%Y%m%d_%H%M%S")

    if not args.skip_gate:
        gate_fixture(args.fixture)

    say("=" * 68)
    say("arm=%s fixture=%s difficulty=%d seeds=%d lanes=%d"
        % (args.arm, args.fixture, args.difficulty, len(seeds), args.lanes))
    say("git=%s  profiles: P1=%s P2=%s" % (sha, args.p1_profile or "default",
                                           args.p2_profile or "default"))
    say("season -> %s" % season)
    say("=" * 68)

    t0 = time.time()
    results: list[dict] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.lanes) as pool:
        futures = {pool.submit(run_one, s, args, stamp, ud, season, sha): s for s in seeds}
        for fut in concurrent.futures.as_completed(futures):
            try:
                results.append(fut.result())
            except Exception as exc:  # noqa: BLE001 — one bad lane must not kill the arm
                say("  [seed %d] lane raised: %s" % (futures[fut], exc))
                results.append({"seed": futures[fut], "status": "error", "note": str(exc)})

    summary = summarise(results, args, sha)
    summary["wall_seconds_total"] = round(time.time() - t0, 1)
    out = os.path.join(season, "campaign_%s_%s_%s.json" % (stamp, args.arm, args.fixture))
    with open(out, "w") as fh:
        json.dump(summary, fh, indent=2)

    say("")
    say("=" * 68)
    say("arm %s on %s — %d games in %.1f min"
        % (args.arm, args.fixture, summary["games"], summary["wall_seconds_total"] / 60.0))
    say("  completed %d, not completed %d  (stalled %d, timed out %d)"
        % (summary["completed"], summary["not_completed"],
           summary["stalled"], summary["timed_out"]))
    if summary["timed_out"]:
        say("  NOTE: a timeout means the box ran out of wall clock while the game was")
        say("        still progressing — usually oversubscribed lanes. Re-run those")
        say("        seeds with fewer lanes or a higher --max-seconds; do NOT read")
        say("        them as AI stalls.")
    if summary["se"] is not None:
        say("  mean margin (P2-P1) = %+.2f   sd %.2f   se %.2f   95%% CI [%+.1f, %+.1f]"
            % (summary["mean_margin_p2_minus_p1"], summary["sd"], summary["se"],
               summary["ci95_low"], summary["ci95_high"]))
        say("  ^ for an A/A arm this is F, the fixture's structural bias")
        say("    (first turn + board side). It should NOT be distinguishable")
        say("    from the F implied by a paired A/B run on the same fixture.")
    say("  summary: %s" % out)
    say("=" * 68)
    return 0


if __name__ == "__main__":
    sys.exit(main())
