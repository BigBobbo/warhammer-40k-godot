#!/usr/bin/env python3
"""Merge BENCH_RESULT lines from sharded head-to-head runs (sibling cloud
sessions running ai_versions.py) into one effect estimate per label.

Each line: BENCH_RESULT {"per_seed": [{"seed", "M1", "M2"}], "split": {...},
"per_card": {...}, "games": n}. Lines are grouped by the label given before
them ("BENCH_SHARD <label> ..." header line) or by --label.

  E per seed = (M1 - M2) / 2 (margin = VP(P2) - VP(P1); E > 0: candidate better)

Usage: python3 tools/ai_lab/bench_merge.py results.txt [more.txt ...]
"""
from __future__ import annotations

import collections
import json
import math
import statistics
import sys


def stats(vals):
    n = len(vals)
    if n < 2:
        return {"n": n, "mean": vals[0] if vals else None}
    m = statistics.fmean(vals)
    sd = statistics.stdev(vals)
    se = sd / math.sqrt(n)
    return {"n": n, "mean": round(m, 2), "sd": round(sd, 2), "se": round(se, 2),
            "ci95": [round(m - 1.96 * se, 2), round(m + 1.96 * se, 2)]}


def main(argv):
    groups = collections.defaultdict(lambda: {"seeds": {}, "split": collections.Counter(), "cards": collections.defaultdict(lambda: [0, 0])})
    label = "?"
    for path in argv or ["-"]:
        fh = sys.stdin if path == "-" else open(path)
        for line in fh:
            line = line.strip()
            if line.startswith("BENCH_SHARD "):
                label = line.split()[1].rsplit("#", 1)[0]
                continue
            i = line.find("BENCH_RESULT ")
            if i < 0:
                continue
            r = json.loads(line[i + len("BENCH_RESULT "):])
            g = groups[label]
            for s in r.get("per_seed", []):
                if s.get("M1") is not None and s.get("M2") is not None:
                    g["seeds"][int(s["seed"])] = (float(s["M1"]), float(s["M2"]))
            for k, v in r.get("split", {}).items():
                g["split"][k] += v
            for c, v in r.get("per_card", {}).items():
                g["cards"][c][0] += v.get("cand", 0)
                g["cards"][c][1] += v.get("base", 0)
    out = {}
    for label, g in groups.items():
        effects = [(m1 - m2) / 2.0 for m1, m2 in g["seeds"].values()]
        n = len(effects)
        sp = g["split"]
        out[label] = {"E": stats(effects),
                      "primary_E": round((sp.get("primary_M1", 0) - sp.get("primary_M2", 0)) / (2 * n), 2) if n else None,
                      "secondary_E": round((sp.get("secondary_M1", 0) - sp.get("secondary_M2", 0)) / (2 * n), 2) if n else None,
                      "wins": sum(1 for m1, m2 in g["seeds"].values() for m in (m1, -m2) if m > 0),
                      "losses": sum(1 for m1, m2 in g["seeds"].values() for m in (m1, -m2) if m < 0),
                      "per_card": {c: {"cand": v[0], "base": v[1]} for c, v in sorted(g["cards"].items(), key=lambda x: x[1][0] - x[1][1])}}
    print(json.dumps(out, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
