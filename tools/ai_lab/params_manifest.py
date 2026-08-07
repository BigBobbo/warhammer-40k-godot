#!/usr/bin/env python3
"""M2 — extract the AI's runtime-tunable parameter surface from the source.

`AIDecisionMaker.gd` declares ~150 `const`s, but only the ones actually read
through `get_param(name, default)` / `get_param_int(name, default)` are
reachable from a profile. A search process that writes a profile key which no
`get_param` ever asks for produces a candidate that lints clean, runs clean,
and changes nothing — burning a full evaluation budget to measure zero.

So the manifest is derived from the CODE, never hand-maintained:

    { "PARAM_NAME": {"kind": "float"|"int", "default": 1.5,
                     "const_name": "...", "call_sites": 3, "lines": [...]} }

Note the difference between a parameter's *declared* const default and the
value `_get_base_param_value` returns for it (0.0 unless the profile or config
sets it). That gap is the silent-zero trap and is why validate_profile.py
refuses `multiply`/`add` on a parameter the profile does not declare.

Usage:
    python3 tools/ai_lab/params_manifest.py                 # human summary
    python3 tools/ai_lab/params_manifest.py --json          # machine-readable
    python3 tools/ai_lab/params_manifest.py --out params_manifest.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SOURCE = os.path.join(REPO, "40k", "scripts", "AIDecisionMaker.gd")

# get_param("NAME", <default expr>)  /  get_param_int("NAME", <default expr>)
CALL_RE = re.compile(r'get_param(_int)?\(\s*"([A-Za-z_][A-Za-z_0-9]*)"\s*,\s*([^,()]*?)\s*\)')
# const NAME := 1.5   |   const NAME: float = 1.5   |   const NAME = 1.5
CONST_RE = re.compile(
    r'^\s*const\s+([A-Z_][A-Z_0-9]*)\s*(?::\s*[A-Za-z_]+\s*)?:?=\s*(-?[0-9.]+)\s*(?:#.*)?$')

# The rule DSL's fixed vocabulary, read straight out of the evaluator so the
# linter cannot drift from the engine.
CONDITION_RE = re.compile(r'^\s*"([a-z_0-9]+)":\s*$')


def parse_consts(src: str) -> dict:
    out = {}
    for line in src.splitlines():
        m = CONST_RE.match(line)
        if m:
            name, raw = m.group(1), m.group(2)
            try:
                out[name] = float(raw) if ("." in raw) else int(raw)
            except ValueError:
                pass
    return out


def parse_condition_types(src: str) -> list:
    """The `match ctype:` arms inside _check_rule_conditions."""
    lines = src.splitlines()
    try:
        start = next(i for i, l in enumerate(lines)
                     if l.startswith("static func _check_rule_conditions"))
    except StopIteration:
        return []
    types = []
    for line in lines[start:]:
        if line.startswith("static func ") and "_check_rule_conditions" not in line:
            break
        m = CONDITION_RE.match(line)
        if m:
            types.append(m.group(1))
    return types


def parse_action_ops(src: str) -> list:
    lines = src.splitlines()
    try:
        start = next(i for i, l in enumerate(lines)
                     if l.startswith("static func _apply_rule_actions"))
    except StopIteration:
        return []
    ops = []
    for line in lines[start:]:
        if line.startswith("static func ") and "_apply_rule_actions" not in line:
            break
        m = CONDITION_RE.match(line)
        if m:
            ops.append(m.group(1))
    return ops


def _dead_conditions(src: str) -> list:
    """vp_* conditions are dead whenever _get_vp_diff reads only the legacy keys.

    Derived, not asserted: if someone reverts _get_vp_diff to the meta.* keys,
    the linter starts flagging vp_* rules again automatically.
    """
    m = re.search(r'static func _get_vp_diff\(.*?\n(?=static func )', src, re.S)
    if not m:
        return []
    body = m.group(0)
    reads_real_vp = 'players' in body and '"vp"' in body
    return [] if reads_real_vp else ["vp_ahead", "vp_behind", "vp_diff_gte", "vp_diff_lte"]


def build_manifest(source: str = SOURCE) -> dict:
    with open(source) as fh:
        src = fh.read()
    consts = parse_consts(src)

    params: dict = {}
    for lineno, line in enumerate(src.splitlines(), start=1):
        for m in CALL_RE.finditer(line):
            is_int = bool(m.group(1))
            name, default_expr = m.group(2), m.group(3).strip()
            entry = params.setdefault(name, {
                "kind": "int" if is_int else "float",
                "default": None,
                "const_name": None,
                "call_sites": 0,
                "lines": [],
            })
            entry["call_sites"] += 1
            entry["lines"].append(lineno)
            if entry["default"] is None:
                if default_expr in consts:
                    entry["default"] = consts[default_expr]
                    entry["const_name"] = default_expr
                else:
                    try:
                        entry["default"] = (int(default_expr) if is_int
                                            else float(default_expr))
                    except ValueError:
                        entry["default"] = None

    return {
        "source": os.path.relpath(source, REPO),
        "parameters": params,
        "condition_types": parse_condition_types(src),
        "action_ops": parse_action_ops(src),
        # Context keys the rule evaluator populates (AIDecisionMaker.gd:1762-1772).
        "context_keys": ["phase", "round", "vp_diff", "units_remaining_pct",
                         "nearest_enemy_inches", "on_objective", "is_melee_unit",
                         "is_vehicle", "unit_points"],
        # Conditions that cannot fire in a live game. This list is derived from
        # _get_vp_diff's source: while it read meta.player1_vp/player2_vp (keys
        # only a test ever wrote), vp_diff was always 0 and every vp_* condition
        # was dead. It now reads state.players[pk].vp, so they work — but the
        # check stays source-derived rather than hardcoded, so the linter tracks
        # the engine instead of drifting from it.
        "dead_condition_types": _dead_conditions(src),
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--out", help="write the manifest JSON here")
    ap.add_argument("--source", default=SOURCE)
    args = ap.parse_args(argv)

    man = build_manifest(args.source)
    if args.out:
        with open(args.out, "w") as fh:
            json.dump(man, fh, indent=2, sort_keys=True)
        print("wrote %s (%d parameters)" % (args.out, len(man["parameters"])))
        return 0
    if args.json:
        print(json.dumps(man, indent=2, sort_keys=True))
        return 0

    params = man["parameters"]
    ints = [n for n, p in params.items() if p["kind"] == "int"]
    no_default = [n for n, p in params.items() if p["default"] is None]
    print("tunable surface of %s" % man["source"])
    print("  %d parameters (%d float, %d int) across %d call sites"
          % (len(params), len(params) - len(ints), len(ints),
             sum(p["call_sites"] for p in params.values())))
    print("  %d rule condition types, %d action ops, %d context keys"
          % (len(man["condition_types"]), len(man["action_ops"]), len(man["context_keys"])))
    if man["dead_condition_types"]:
        print("  DEAD condition types (vp_diff is always 0 in live play): %s"
              % ", ".join(man["dead_condition_types"]))
    if no_default:
        print("  %d parameter(s) whose default could not be resolved statically: %s"
              % (len(no_default), ", ".join(sorted(no_default)[:5])))
    print("\n  highest-traffic parameters (call sites — a rough proxy for influence,")
    print("  NOT a substitute for the M3 sensitivity screen):")
    for name, p in sorted(params.items(), key=lambda kv: -kv[1]["call_sites"])[:15]:
        print("    %-48s %2d sites  default=%s" % (name, p["call_sites"], p["default"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
