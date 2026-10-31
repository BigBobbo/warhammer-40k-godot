#!/usr/bin/env python3
"""Batch counterfactual rollouts for LLM-critic findings, shardable across machines.

  pack   gather the value jobs of a critic sweep (tools/llm_critic/sweep.py),
         filter them, and copy each job's case (JSON + .w40ksave + .meta) into
         40k/tests/rollout_cases/<label>/ with a jobs.json, so another machine
         (a sibling cloud session) can run them from a git checkout.
  run    run one shard of a jobs.json (rollout.py per job) and print one
         ROLLOUT_RESULT line per job plus SHARD_DONE.
  table  merge ROLLOUT_RESULT lines (files or stdin) into a ranked table.

Usage:
  python3 tools/ai_lab/rollout_batch.py pack --sweep 40k/tools/llm_critic/runs/sweep_sweep1.json --label sweep1 [--min-severity 2]
  python3 tools/ai_lab/rollout_batch.py run --jobs 40k/tests/rollout_cases/sweep1/jobs.json --shard 0/8 --seeds 12 --horizon 1
  python3 tools/ai_lab/rollout_batch.py table results*.txt
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CASES_ROOT = os.path.join(REPO, "40k", "tests", "rollout_cases")


def cmd_pack(args) -> int:
    sweep = json.load(open(args.sweep))
    out_dir = os.path.join(CASES_ROOT, args.label)
    os.makedirs(out_dir, exist_ok=True)
    jobs = []
    for entry in sweep:
        if not entry or entry.get("status") != "ok":
            continue
        run_dir = entry["run_dir"]
        vj = os.path.join(run_dir, "value_jobs.json")
        if not os.path.exists(vj):
            continue
        for j in json.load(open(vj)):
            if j.get("verdict") not in args.verdicts.split(","):
                continue
            if int(j.get("severity") or 0) < args.min_severity:
                continue
            case = json.load(open(j["case"]))
            src_dir = os.path.dirname(j["case"])
            name = "%s__%s" % (os.path.basename(run_dir.rstrip("/")), j["job"])
            shutil.copy(j["case"], os.path.join(out_dir, name + ".json"))
            save = os.path.join(src_dir, case["save_file"])
            shutil.copy(save, os.path.join(out_dir, case["save_file"]))
            meta = os.path.splitext(save)[0] + ".meta"
            if os.path.exists(meta):
                shutil.copy(meta, os.path.join(out_dir, os.path.basename(meta)))
            jobs.append({"job": name, "case": name + ".json", "alt": j["alt"], "verdict": j.get("verdict"),
                         "severity": j.get("severity"), "summary": j.get("summary", ""),
                         "better_option": j.get("better_option", ""), "config": entry.get("config", {}),
                         "run_dir": os.path.basename(run_dir.rstrip("/"))})
    json.dump(jobs, open(os.path.join(out_dir, "jobs.json"), "w"), indent=1)
    print("packed %d job(s) into %s" % (len(jobs), out_dir))
    return 0


def cmd_run(args) -> int:
    jobs_path = os.path.abspath(args.jobs)
    jobs = json.load(open(jobs_path))
    k, n = (int(x) for x in args.shard.split("/"))
    mine = [j for i, j in enumerate(jobs) if i % n == k]
    base = os.path.dirname(jobs_path)
    out_dir = args.out_dir or ("/tmp/rollout_shard_%d" % k)
    os.makedirs(out_dir, exist_ok=True)
    rollout = os.path.join(HERE, "rollout.py")
    for j in mine:
        out = os.path.join(out_dir, j["job"] + ".json")
        if not os.path.exists(out):
            subprocess.run([sys.executable, rollout, "run", "--case", os.path.join(base, j["case"]),
                            "--alt", json.dumps(j["alt"]), "--seeds", str(args.seeds), "--seed-base", str(args.seed_base),
                            "--horizon", str(args.horizon), "--lanes", str(args.lanes),
                            "--tag", "batch_" + j["job"], "--out", out],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        res = {"job": j["job"], "status": "missing"}
        if os.path.exists(out):
            s = json.load(open(out))
            ev = s.get("effect_value", {})
            res = {"job": j["job"], "status": "ok", "E": ev.get("mean"), "se": ev.get("se"), "ci": ev.get("ci95"),
                   "n": ev.get("n"), "A": s.get("A", {}).get("value", {}).get("mean"),
                   "B": s.get("B", {}).get("value", {}).get("mean"),
                   "mat": s.get("effect_material", {}).get("mean"),
                   "drift": not s.get("drift", {}).get("reproduced", False),
                   "a_did": str(s.get("drift", {}).get("a_did", ""))[:110],
                   "applied": sum(1 for x in s.get("override_applied", []) if x),
                   "identical": s.get("identical_pairs")}
        print("ROLLOUT_RESULT " + json.dumps(res, separators=(",", ":")), flush=True)
    print("SHARD_DONE %d/%d jobs=%d" % (k, n, len(mine)), flush=True)
    return 0


def cmd_table(args) -> int:
    rows = {}
    srcs = args.files or ["-"]
    for src in srcs:
        fh = sys.stdin if src == "-" else open(src)
        for line in fh:
            i = line.find("ROLLOUT_RESULT ")
            if i >= 0:
                r = json.loads(line[i + len("ROLLOUT_RESULT "):].strip())
                rows[r["job"]] = r
    meta = {}
    if args.jobs:
        for j in json.load(open(args.jobs)):
            meta[j["job"]] = j
    ok = [r for r in rows.values() if r.get("status") == "ok" and r.get("E") is not None]
    ok.sort(key=lambda r: -float(r["E"]))
    for r in ok:
        m = meta.get(r["job"], {})
        print("%+6.2f [%6.2f, %6.2f] n=%s drift=%s same=%s  %s  | %s" % (
            r["E"], r["ci"][0] if r.get("ci") else float("nan"), r["ci"][1] if r.get("ci") else float("nan"),
            r.get("n"), r.get("drift"), r.get("identical"), r["job"][:60], str(m.get("better_option", ""))[:70]))
    missing = [r["job"] for r in rows.values() if r.get("status") != "ok"]
    if missing:
        print("missing: %s" % ", ".join(missing))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("pack")
    p.add_argument("--sweep", required=True)
    p.add_argument("--label", required=True)
    p.add_argument("--verdicts", default="flawed,questionable")
    p.add_argument("--min-severity", type=int, default=1)
    r = sub.add_parser("run")
    r.add_argument("--jobs", required=True)
    r.add_argument("--shard", default="0/1")
    r.add_argument("--seeds", type=int, default=12)
    r.add_argument("--seed-base", type=int, default=5000)
    r.add_argument("--horizon", type=int, default=1)
    r.add_argument("--lanes", type=int, default=4)
    r.add_argument("--out-dir", default="")
    t = sub.add_parser("table")
    t.add_argument("files", nargs="*")
    t.add_argument("--jobs", default="")
    args = ap.parse_args(argv)
    return {"pack": cmd_pack, "run": cmd_run, "table": cmd_table}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
