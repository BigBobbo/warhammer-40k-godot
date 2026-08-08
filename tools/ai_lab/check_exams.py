#!/usr/bin/env python3
"""Static pre-flight for the tactical exam suite — no Godot, runs in a second.

An exam that names a unit its fixture does not contain does not fail loudly.
`st.units["U_GONE"]` raises inside the setup snippet, the exam reports ERROR
with no verdict, and you find out roughly two minutes later — per exam, times
however many you broke. Migrating the suite from the 1335-pt Custodes mirror to
the 2000-pt fixtures renamed or removed most of the unit ids at once
(`MIR_U_*` -> `U_*_P2`, and Caladius / Telemon / Witchseekers no longer exist),
which is exactly the situation this catches for free.

Checks, in order of how expensive they are to discover the slow way:

  1. the fixture named by the exam exists and parses;
  2. every `U_*` id mentioned in `setup` or `assert` exists in that fixture;
  3. `phase` is a real GameState.Phase, and a phase-1 exam runs on a fixture
     that actually starts at deployment (a deployment exam pointed at a
     post-deployment save silently grades an empty phase);
  4. the JSON has the keys the runner requires.

Usage:
    python3 tools/ai_lab/check_exams.py            # gated + aspirational
    python3 tools/ai_lab/check_exams.py --json

Exit 0 iff every exam passed.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

from fixture_check import load_save  # noqa: E402

EXAM_DIRS = [
    os.path.join(REPO, "40k", "tests", "exams"),
    os.path.join(REPO, "40k", "tests", "exams", "aspirational"),
]
SAVES = os.path.join(REPO, "40k", "tests", "saves")

# GameState.Phase (autoloads/GameState.gd:16)
PHASES = {
    0: "FORMATIONS", 1: "DEPLOYMENT", 2: "REDEPLOYMENT", 3: "ROLL_OFF",
    4: "SCOUT", 5: "SCOUT_MOVES", 6: "COMMAND", 7: "MOVEMENT", 8: "SHOOTING",
    9: "CHARGE", 10: "FIGHT", 11: "SCORING", 12: "MORALE",
    13: "FIRST_TURN_ROLLOFF",
}
REQUIRED_KEYS = ("id", "fixture", "phase", "assert")
UNIT_RE = re.compile(r"\b(?:MIR_)?U_[A-Z0-9_\-]+")

_fixture_cache: dict = {}


def fixture(name: str) -> dict:
    if name not in _fixture_cache:
        _fixture_cache[name] = load_save(os.path.join(SAVES, name + ".w40ksave"))
    return _fixture_cache[name]


def check(path: str) -> list:
    errs = []
    try:
        d = json.load(open(path))
    except Exception as exc:  # noqa: BLE001
        return ["unparseable JSON: %s" % exc]

    for k in REQUIRED_KEYS:
        if k not in d:
            errs.append("missing required key %r" % k)
    if errs:
        return errs

    fx = d["fixture"]
    if not os.path.exists(os.path.join(SAVES, fx + ".w40ksave")):
        return ["fixture %r does not exist in 40k/tests/saves/" % fx]
    try:
        save = fixture(fx)
    except Exception as exc:  # noqa: BLE001
        return ["fixture %r did not parse: %s" % (fx, exc)]

    have = set(save.get("units") or {})
    body = json.dumps(d.get("setup", [])) + json.dumps(d["assert"])
    for ref in sorted(set(UNIT_RE.findall(body))):
        if ref not in have:
            errs.append("references %s, which %s does not contain" % (ref, fx))

    phase = int(d["phase"])
    if phase not in PHASES:
        errs.append("phase=%d is not a GameState.Phase" % phase)
    fx_phase = int((save.get("meta") or {}).get("phase", -1) or -1)
    if phase == 1 and fx_phase != 1:
        errs.append("phase=1 (DEPLOYMENT) but %s starts at phase %d (%s) with the "
                    "armies already placed — the exam would grade an empty phase"
                    % (fx, fx_phase, PHASES.get(fx_phase, "?")))
    return errs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    specs = []
    for d in EXAM_DIRS:
        specs.extend(sorted(glob.glob(os.path.join(d, "*.json"))))
    if not specs:
        print("no exams found", file=sys.stderr)
        return 2

    results = []
    failed = 0
    for spec in specs:
        errs = check(spec)
        failed += bool(errs)
        results.append({"exam": os.path.basename(spec), "ok": not errs, "errors": errs})

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        for r in results:
            print("  [%s] %s" % ("PASS" if r["ok"] else "FAIL", r["exam"]))
            for e in r["errors"]:
                print("         %s" % e)
        print("\n%d exam(s) checked, %d failed" % (len(results), failed))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
