#!/usr/bin/env python3
"""LLM-critic sweep: many critic games side by side, each in its own windowed
Godot process with its own MCP bridge port (GODOT_MCP_PORT / CRITIC_BRIDGE_PORT).

For every config: start the game, wait for the bridge, run
`critic.py all --no-synth` (collect + review + report) and `critic.py value`
(rollout jobs from each flagged review's machine-readable alternative), stop
the game. A config is one matchup + deployment + dispositions + seed list.

Usage:
  python3 tools/llm_critic/sweep.py --plan sweep.json --parallel 3 --label sweep1
  sweep.json: [{"army1": "custodes_lions", "army2": "Orks_2000", "zone": "crucible_of_battle",
                "disposition1": "take_and_hold", "disposition2": "purge_the_foe", "seeds": "7101"}, ...]
Writes sweep_<label>.json with the run dir of each config.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import signal
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", ".."))
_lock = threading.Lock()


def say(msg):
    with _lock:
        print(msg, flush=True)


def run_config(i, cfg, port, args):
    tag = "%s_%02d" % (args.label, i)
    log_path = os.path.join(args.log_dir, tag + "_game.log")
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/bin") + os.pathsep + env.get("PATH", "")
    env["GODOT_MCP_PORT"] = str(port)
    env["GODOT_MCP_ENABLED"] = "1"
    game = subprocess.Popen(["godot", "--path", PROJECT, "--rendering-method", "gl_compatibility"],
                            stdout=open(log_path, "w"), stderr=subprocess.STDOUT, env=env,
                            start_new_session=True)
    try:
        t0 = time.time()
        while time.time() - t0 < 300:
            if "GodotMCP] Listening on 127.0.0.1:%d" % port in open(log_path, errors="replace").read():
                break
            if game.poll() is not None:
                raise RuntimeError("game exited before the bridge came up")
            time.sleep(1)
        else:
            raise RuntimeError("bridge did not come up on port %d" % port)
        say("[%s] game up on port %d: %s" % (tag, port, json.dumps(cfg)))
        cenv = dict(env)
        cenv["CRITIC_BRIDGE_PORT"] = str(port)
        cmd = [sys.executable, os.path.join(HERE, "critic.py"), "all", "--no-synth",
               "--label", tag, "--seeds", str(cfg.get("seeds", "7001")),
               "--army1", cfg.get("army1", "custodes_lions"), "--army2", cfg.get("army2", cfg.get("army1", "custodes_lions")),
               "--zone", cfg.get("zone", "crucible_of_battle"), "--layout", cfg.get("layout", ""),
               "--mission", cfg.get("mission", "take_and_hold"),
               "--disposition1", cfg.get("disposition1", ""), "--disposition2", cfg.get("disposition2", ""),
               "--layout-variant", str(cfg.get("layout_variant", 1)),
               "--max-round", str(cfg.get("max_round", args.max_round)),
               "--per-phase", str(cfg.get("per_phase", args.per_phase)),
               "--time-scale", str(args.time_scale), "--jobs", str(args.review_jobs),
               "--review-model", args.review_model]
        out = subprocess.run(cmd, cwd=PROJECT, env=cenv, capture_output=True, text=True,
                             timeout=args.config_timeout)
        clog = os.path.join(args.log_dir, tag + "_critic.log")
        open(clog, "w").write(out.stdout + "\n--- stderr ---\n" + out.stderr)
        run_dir = ""
        for line in out.stdout.splitlines():
            if line.startswith("run dir: "):
                run_dir = line[len("run dir: "):].strip()
        if not run_dir:
            raise RuntimeError("critic did not report a run dir (see %s)" % clog)
        v = subprocess.run([sys.executable, os.path.join(HERE, "critic.py"), "value", run_dir],
                           cwd=PROJECT, env=cenv, capture_output=True, text=True, timeout=600)
        say("[%s] done: %s | %s" % (tag, run_dir, v.stdout.strip().splitlines()[-1] if v.stdout.strip() else ""))
        return {"config": cfg, "port": port, "run_dir": run_dir, "status": "ok"}
    except Exception as exc:  # noqa: BLE001
        say("[%s] FAILED: %s" % (tag, exc))
        return {"config": cfg, "port": port, "status": "failed", "error": str(exc)}
    finally:
        try:
            os.killpg(game.pid, signal.SIGTERM)
        except OSError:
            pass


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--plan", required=True, help="JSON list of configs")
    ap.add_argument("--label", default="sweep")
    ap.add_argument("--parallel", type=int, default=3)
    ap.add_argument("--base-port", type=int, default=9180)
    ap.add_argument("--max-round", type=int, default=3)
    ap.add_argument("--per-phase", type=int, default=2)
    ap.add_argument("--time-scale", type=float, default=2.0)
    ap.add_argument("--review-jobs", type=int, default=3)
    ap.add_argument("--review-model", default="claude-sonnet-5-5")
    ap.add_argument("--config-timeout", type=float, default=7200)
    ap.add_argument("--log-dir", default="")
    args = ap.parse_args(argv)
    configs = json.load(open(args.plan))
    args.log_dir = args.log_dir or os.path.join(HERE, "runs", "sweep_logs_" + args.label)
    os.makedirs(args.log_dir, exist_ok=True)
    results = [None] * len(configs)
    free_ports = list(range(args.base_port, args.base_port + args.parallel))
    port_lock = threading.Lock()

    def job(i):
        with port_lock:
            port = free_ports.pop()
        try:
            return i, run_config(i, configs[i], port, args)
        finally:
            with port_lock:
                free_ports.append(port)

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.parallel) as pool:
        for i, res in pool.map(job, range(len(configs))):
            results[i] = res
    out = os.path.join(HERE, "runs", "sweep_%s.json" % args.label)
    json.dump(results, open(out, "w"), indent=1)
    say("sweep summary: %s (%d ok, %d failed)" % (out, sum(1 for r in results if r and r.get("status") == "ok"),
                                                  sum(1 for r in results if not r or r.get("status") != "ok")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
