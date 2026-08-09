#!/usr/bin/env python3
"""A7 — reachability and record integrity can only improve.

Two things this repo has just spent real effort on rot silently if nothing
watches them:

  * **Reachability.** 78% of the AI's scoring arithmetic was bare literals no
    profile, rule or optimiser could touch. A4 and A5 brought that to 42% by
    promoting 109 coefficients. Nothing stops the next edit from writing
    `score += 3.0` again, and nothing would notice.
  * **Instrumentation.** A1-A3 made the decision records honest — real
    alternatives, decomposed scores, `parameters_used` read off the resolver.
    A refactor that drops a term or re-hardcodes a name breaks every offline
    analysis downstream, quietly and much later.

So this is a ratchet, not a threshold. It compares the current source against
`tools/ai_lab/ratchet.json` and fails when a number moves the wrong way. The
baseline file is committed and is meant to be updated **deliberately**, in the
same commit as the change that justifies it, so a regression is a thing
somebody wrote down rather than a thing that happened.

Static analysis only: no games, no Godot, seconds to run.

Usage:
    python3 tools/ai_lab/ratchet_check.py            # check
    python3 tools/ai_lab/ratchet_check.py --update   # re-baseline, deliberately
    python3 tools/ai_lab/ratchet_check.py --json
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
sys.path.insert(0, HERE)

from params_manifest import build_manifest  # noqa: E402
from tunability_audit import scan as tunability_scan  # noqa: E402

RATCHET = os.path.join(HERE, "ratchet.json")
AIDM = os.path.join(REPO, "40k", "scripts", "AIDecisionMaker.gd")

# Instrumentation the records depend on. Each is a function name that must keep
# being called from AIDecisionMaker, with the minimum number of call sites seen
# when the ratchet was set. These are the load-bearing pieces of A1-A3: drop
# one and the records go quiet without any test failing.
INSTRUMENTATION = {
    "_add_decision_record": "every recorded decision",
    "_t_add": "A2 additive score decomposition",
    "_t_mul": "A2 multiplicative score decomposition",
    "_note_param_read": "A3 parameters_used, read off the resolver",
    "_stash_shooting_alternatives": "A1 shooting alternatives capture",
}

# Decision types that must keep being emitted. A type disappearing from the
# source is exactly the silent regression this exists to catch.
DECISION_TYPES = ("movement", "shooting", "hold_fire", "charge", "fight")


def measure() -> dict:
    src = io.open(AIDM, encoding="utf-8").read()
    manifest = build_manifest()
    audit = tunability_scan()

    counts = {name: len(re.findall(r"\b%s\(" % re.escape(name), src))
              for name in INSTRUMENTATION}
    # A definition is also a match; the ratchet cares about USE sites.
    for name in counts:
        if re.search(r"^static func %s\(" % re.escape(name), src, re.M):
            counts[name] -= 1

    types_present = sorted({t for t in DECISION_TYPES
                            if '_add_decision_record("%s"' % t in src})

    return {
        "parameters": len(manifest["parameters"]),
        "call_sites": sum(p["call_sites"] for p in manifest["parameters"].values()),
        "unreachable_coefficients": len(audit["hardcoded"]),
        "unreachable_share_pct": round(100.0 * len(audit["hardcoded"]) / max(
            1, len(audit["hardcoded"]) + len(audit["tunable"]) + len(audit["named_const"])), 1),
        "instrumentation_call_sites": counts,
        "decision_types_emitted": types_present,
    }


# (key, direction) — "up" means the number may only rise, "down" only fall.
DIRECTIONS = [
    ("parameters", "up"),
    ("call_sites", "up"),
    ("unreachable_coefficients", "down"),
    ("unreachable_share_pct", "down"),
]


def check(now: dict, base: dict) -> list:
    problems = []
    for key, direction in DIRECTIONS:
        a, b = now.get(key), base.get(key)
        if a is None or b is None:
            continue
        if direction == "up" and a < b:
            problems.append("%s fell %s -> %s (may only rise)" % (key, b, a))
        if direction == "down" and a > b:
            problems.append("%s rose %s -> %s (may only fall)" % (key, b, a))

    for name, why in INSTRUMENTATION.items():
        a = now["instrumentation_call_sites"].get(name, 0)
        b = base.get("instrumentation_call_sites", {}).get(name, 0)
        if a < b:
            problems.append("%s call sites fell %d -> %d — %s" % (name, b, a, why))

    missing = set(base.get("decision_types_emitted", [])) - set(now["decision_types_emitted"])
    if missing:
        problems.append("decision types no longer emitted: %s" % ", ".join(sorted(missing)))
    return problems


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--update", action="store_true",
                    help="re-baseline. Do this in the SAME commit as the change "
                         "that justifies it, and say why in the message.")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    now = measure()
    if args.update or not os.path.exists(RATCHET):
        with io.open(RATCHET, "w", encoding="utf-8") as fh:
            json.dump({
                "note": ("Baseline for tools/ai_lab/ratchet_check.py. Reachability and "
                         "instrumentation may only improve. Update this file DELIBERATELY, "
                         "in the same commit as the justified regression, with the reason "
                         "in the commit message."),
                **now}, fh, indent=2)
            fh.write("\n")
        print("ratchet baseline written to %s" % os.path.relpath(RATCHET, REPO))
        print(json.dumps(now, indent=2))
        return 0

    base = json.load(io.open(RATCHET, encoding="utf-8"))
    problems = check(now, base)

    if args.json:
        print(json.dumps({"now": now, "baseline": base, "problems": problems}, indent=2))
        return 1 if problems else 0

    print("=" * 74)
    print("AI-LAB RATCHET")
    print("=" * 74)
    for key, direction in DIRECTIONS:
        print("  %-28s %8s  (was %s, may only go %s)"
              % (key, now.get(key), base.get(key), direction))
    print("  %-28s %s" % ("decision types emitted", ", ".join(now["decision_types_emitted"])))
    print("  instrumentation call sites:")
    for name in sorted(INSTRUMENTATION):
        print("    %-32s %4d  (was %s)" % (name, now["instrumentation_call_sites"].get(name, 0),
                                           base.get("instrumentation_call_sites", {}).get(name, "?")))
    print()
    if problems:
        for p in problems:
            print("  [FAIL] %s" % p)
        print("\n  If this regression is intended, re-run with --update IN THE SAME")
        print("  COMMIT and say why. A ratchet you can move silently is not a ratchet.")
        print("=" * 74)
        return 1
    print("  [PASS] nothing moved the wrong way")
    print("=" * 74)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
