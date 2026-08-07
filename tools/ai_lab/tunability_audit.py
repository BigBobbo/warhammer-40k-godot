#!/usr/bin/env python3
"""Find scoring the optimiser can never reach — mechanically, with no LLM.

The concern this answers: tuning 104 constants is local search inside a fixed
space, so we may be climbing a hill while a better one sits behind a wall we
cannot see. feature_census.py measures one wall (the AI reports 12 distinct
scoring terms). This measures the other, and it is the taller one.

A coefficient only enters the search space if it is read through
`get_param()` / `get_param_int()`. A bare numeric literal in score arithmetic
is invisible to every profile, every rule, and every optimiser — no campaign,
at any games budget, can move it. Measured at 60ce588: 243 of 289 compound
score assignments use a bare literal. **84% of the scoring arithmetic cannot
be tuned at all.**

That reframes the roadmap. Before spending 1,500-3,500 games searching over
the reachable 16%, it is far cheaper to ask which of the unreachable 84%
deserve a `get_param` — promoting a literal to a parameter costs one line and
immediately enlarges the space the search runs in.

This is deliberately the CHEAP baseline for "not expressible". An LLM audit
should be reserved for the genuinely harder question — considerations the AI
has no term for at all — and should not be spent rediscovering what this grep
finds for free.

Heuristics and their limits: only compound assignments (`+=`, `-=`, `*=`) onto
an identifier containing score/value/priority are counted, and lines whose
right-hand side names an ALL_CAPS constant are skipped as "at least
reviewable". So this UNDERCOUNTS: magic numbers inside helper functions,
comparisons, and thresholds are not seen. Treat the output as a floor.

Usage:
    python3 tools/ai_lab/tunability_audit.py
    python3 tools/ai_lab/tunability_audit.py --top 40
    python3 tools/ai_lab/tunability_audit.py --json
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SOURCE = os.path.join(REPO, "40k", "scripts", "AIDecisionMaker.gd")

ACC = re.compile(r'^\s*\w*(?:score|value|priority)\w*\s*(\+=|-=|\*=)\s*(.+?)(?:\s*#\s*(.*))?$', re.I)
NUMERIC = re.compile(r'(?<![\w.])\d+(?:\.\d+)?(?![\w.])')
CONST = re.compile(r'[A-Z][A-Z_0-9]{3,}')


def scan(source: str = SOURCE) -> dict:
    lines = io.open(source, encoding="utf-8").read().splitlines()
    tunable, named_const, hardcoded = [], [], []

    # Track the enclosing function so findings are attributable to a subsystem.
    func = "<module>"
    for i, line in enumerate(lines, 1):
        fm = re.match(r'^(?:static\s+)?func\s+(\w+)', line)
        if fm:
            func = fm.group(1)
        m = ACC.match(line)
        if not m:
            continue
        op, rhs, comment = m.group(1), m.group(2), (m.group(3) or "")
        entry = {"line": i, "func": func, "op": op,
                 "code": line.strip(), "comment": comment.strip()}
        if "get_param" in rhs:
            tunable.append(entry)
        elif CONST.search(rhs):
            named_const.append(entry)
        elif NUMERIC.search(rhs):
            hardcoded.append(entry)

    by_func: dict[str, int] = {}
    for e in hardcoded:
        by_func[e["func"]] = by_func.get(e["func"], 0) + 1

    total = len(tunable) + len(hardcoded)
    return {
        "source": os.path.relpath(source, REPO),
        "tunable": tunable,
        "named_const": named_const,
        "hardcoded": hardcoded,
        "unreachable_pct": round(100.0 * len(hardcoded) / total, 1) if total else 0.0,
        "hardcoded_by_function": dict(sorted(by_func.items(), key=lambda kv: -kv[1])),
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--top", type=int, default=20, help="functions / lines to list")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--source", default=SOURCE)
    args = ap.parse_args(argv)

    r = scan(args.source)
    if args.json:
        print(json.dumps(r, indent=2))
        return 0

    print("=" * 74)
    print("TUNABILITY AUDIT — %s" % r["source"])
    print("=" * 74)
    print("\n  score arithmetic with a get_param coefficient  (TUNABLE) ... %d" % len(r["tunable"]))
    print("  score arithmetic with a bare numeric coefficient (NOT)  ... %d" % len(r["hardcoded"]))
    print("  score arithmetic referencing a named const (reviewable) ... %d" % len(r["named_const"]))
    print("\n  ==> %.0f%% of the scoring arithmetic is unreachable by ANY profile," % r["unreachable_pct"])
    print("      rule, or optimiser, at any games budget.")

    print("\n\nWHERE THE UNREACHABLE COEFFICIENTS LIVE")
    print("-" * 74)
    for fn, n in list(r["hardcoded_by_function"].items())[: args.top]:
        print("   %-46s %d" % (fn, n))

    print("\n\nHIGHEST-VALUE PROMOTIONS (a literal -> get_param is one line)")
    print("-" * 74)
    print("   Listing coefficients that carry an explanatory comment: the author already")
    print("   knew these were judgement calls, which makes them the obvious candidates.\n")
    shown = 0
    for e in r["hardcoded"]:
        if not e["comment"] or shown >= args.top:
            continue
        print("   :%-6d %-34s %s" % (e["line"], e["func"], e["code"][:60]))
        print("           # %s" % e["comment"][:76])
        shown += 1

    print("\n" + "=" * 74)
    print("   Promoting a literal costs one line and immediately enlarges the space the")
    print("   search runs in. Doing that BEFORE a 1,500-3,500 game campaign is far")
    print("   cheaper than discovering afterwards that the campaign was confined to 16%.")
    print("   Undercounts by construction — see the module docstring.")
    print("=" * 74)
    return 0


if __name__ == "__main__":
    sys.exit(main())
