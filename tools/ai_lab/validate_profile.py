#!/usr/bin/env python3
"""M2 — lint an AI profile against the engine's real parameter/DSL surface.

`ProfileManager.validate_profile()` (scripts/ProfileManager.gd:111-137) checks
STRUCTURE ONLY: format tag, version, a profile_name, that parameters is a
Dictionary and rules is an Array with ids/conditions/actions. It validates
none of the things a machine-generated profile actually gets wrong. A profile
can pass it and silently do nothing — or, worse, silently do the opposite of
what it says.

The three traps, all verified in scripts/AIDecisionMaker.gd:

  1. SILENT ZERO (:416-426). `_get_base_param_value` returns 0.0 for any
     parameter that is not in a profile's own `parameters` map or in
     ai_config.json — including every parameter whose only value is a `const`
     default. So `{"type": "multiply", "param": "WEIGHT_CONTESTED_OBJ",
     "value": 1.2}` does not scale 8.0 to 9.6. It computes 0.0 * 1.2 = 0.0 and
     TURNS THE WEIGHT OFF. `add` is the same trap in a quieter costume: it
     yields the bare addend, discarding the const default.

  2. UNKNOWN CONDITIONS PASS (:346-391). `_check_rule_conditions` is a `match`
     with no default arm, so a misspelled or invented condition type does not
     fail the rule — it falls through and the condition is treated as MET.
     A rule guarded by `{"type": "round_gt", ...}` (not a real type; the real
     one is `round_gte`) fires unconditionally, in every round.

  3. UNKNOWN ACTIONS VANISH (:393-414). An action whose `type` is not
     override/multiply/add matches no arm and is silently dropped.

Plus one dead surface: `vp_diff` is always 0 in live play. `_get_vp_diff`
(:1182-1189) reads `meta.player1_vp` / `meta.player2_vp`, and a repo-wide
search shows those keys are written by exactly one test
(tests/test_ai_movement_coordination.gd:50). Real VP lives at
`GameState.state.players[pk].vp`. Every `vp_*` condition is therefore a no-op
in a real game — `vp_ahead` and `vp_diff_gte` never fire, and `vp_behind` /
`vp_diff_lte` fire ALWAYS, because 0 >= 0 and 0 <= 0.

A search process generating profiles will hit all four. Without this linter it
spends the evaluation budget measuring the noise floor and concludes, honestly
and wrongly, that nothing helps.

Usage:
    python3 tools/ai_lab/validate_profile.py 40k/tests/bench_profiles/*.json
    python3 tools/ai_lab/validate_profile.py cand.json --json
    python3 tools/ai_lab/validate_profile.py --selftest

Exit 0 = every profile clean, 1 = at least one error (warnings alone pass
unless --strict).
"""
from __future__ import annotations

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
AI_CONFIG = os.path.join(REPO, "40k", "data", "ai_config.json")

sys.path.insert(0, HERE)
from params_manifest import build_manifest  # noqa: E402

FORMAT_TAG = "wh40k_ai_profile"


class Lint:
    def __init__(self, path: str):
        self.path = path
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def err(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    @property
    def ok(self) -> bool:
        return not self.errors

    def as_dict(self) -> dict:
        return {"path": self.path, "ok": self.ok,
                "errors": self.errors, "warnings": self.warnings}


def load_config_params() -> set:
    """Parameters that ai_config.json gives a non-const base value.

    These are the only names beyond a profile's own `parameters` map for which
    `_get_base_param_value` returns something other than 0.0.
    """
    try:
        with open(AI_CONFIG) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return set()
    params = data.get("parameters", data)
    return set(params) if isinstance(params, dict) else set()


def lint_profile(data: dict, path: str, manifest: dict,
                 config_params: set, require_metadata: bool = True) -> Lint:
    lint = Lint(path)
    known = manifest["parameters"]
    cond_types = set(manifest["condition_types"])
    action_ops = set(manifest["action_ops"])
    dead_conds = set(manifest["dead_condition_types"])

    if not isinstance(data, dict):
        lint.err("profile is not a JSON object")
        return lint

    # --- structural (mirrors ProfileManager.validate_profile) --------------
    if data.get("format", "") != FORMAT_TAG:
        msg = "format is %r, expected %r" % (data.get("format", "<missing>"), FORMAT_TAG)
        (lint.err if require_metadata else lint.warn)(msg)
    if require_metadata:
        if not isinstance(data.get("version"), (int, float)):
            lint.err("missing or non-numeric 'version'")
        if not str(data.get("profile_name", "")).strip():
            lint.err("missing or empty 'profile_name'")

    params = data.get("parameters", {})
    if not isinstance(params, dict):
        lint.err("'parameters' must be an object")
        params = {}
    rules = data.get("rules", [])
    if not isinstance(rules, list):
        lint.err("'rules' must be an array")
        rules = []

    # --- parameters ---------------------------------------------------------
    for name, value in params.items():
        if name not in known:
            lint.err("parameter %r is never read by get_param() — it will have "
                     "no effect. Run tools/ai_lab/params_manifest.py for the "
                     "%d readable names." % (name, len(known)))
            continue
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            lint.err("parameter %r has non-numeric value %r" % (name, value))
            continue
        if known[name]["kind"] == "int" and float(value) != int(value):
            lint.warn("parameter %r is read via get_param_int(); %r will be "
                      "truncated to %d" % (name, value, int(value)))

    # Everything the engine will resolve to a real base value.
    declared = set(params) | set(config_params)

    # --- rules --------------------------------------------------------------
    seen_ids = set()
    for i, rule in enumerate(rules):
        if not isinstance(rule, dict):
            lint.err("rule[%d] is not an object" % i)
            continue
        rid = rule.get("id", "") or rule.get("name", "") or str(i)
        if not str(rule.get("id", "")).strip():
            lint.err("rule[%d] (%r) has no 'id'" % (i, rid))
        elif rule["id"] in seen_ids:
            lint.err("rule[%d]: duplicate id %r" % (i, rule["id"]))
        else:
            seen_ids.add(rule["id"])

        if "priority" in rule and not isinstance(rule["priority"], (int, float)):
            lint.err("rule %r: 'priority' must be numeric (unsorted rules apply "
                     "in file order)" % rid)
        if "enabled" in rule and not isinstance(rule["enabled"], bool):
            lint.err("rule %r: 'enabled' must be a boolean" % rid)

        conditions = rule.get("conditions")
        if not isinstance(conditions, list):
            lint.err("rule %r: missing or non-array 'conditions'" % rid)
            conditions = []
        actions = rule.get("actions")
        if not isinstance(actions, list):
            lint.err("rule %r: missing or non-array 'actions'" % rid)
            actions = []

        if conditions == []:
            lint.warn("rule %r has no conditions — it fires in every context, "
                      "which makes it a plain parameter override with extra steps" % rid)

        # ---- TRAP 2: unknown condition types PASS --------------------------
        for j, cond in enumerate(conditions):
            if not isinstance(cond, dict):
                lint.err("rule %r condition[%d] is not an object" % (rid, j))
                continue
            ctype = cond.get("type", "")
            if ctype not in cond_types:
                lint.err("rule %r condition[%d]: unknown type %r. Unknown types "
                         "do NOT fail the rule — _check_rule_conditions has no "
                         "default arm, so this condition is treated as MET and "
                         "the rule fires unconditionally. Valid: %s"
                         % (rid, j, ctype, ", ".join(sorted(cond_types))))
                continue
            if ctype in dead_conds:
                lint.err("rule %r condition[%d]: %r can never work — vp_diff is "
                         "always 0 in a live game (_get_vp_diff reads "
                         "meta.player1_vp/player2_vp, which only a test writes; "
                         "real VP lives at GameState.state.players[pk].vp). "
                         "'vp_ahead'/'vp_diff_gte' never fire; "
                         "'vp_behind'/'vp_diff_lte' fire ALWAYS."
                         % (rid, j, ctype))
            # value-bearing conditions need a value
            if ctype not in ("on_objective", "is_melee_unit", "is_vehicle",
                             "vp_ahead", "vp_behind"):
                if cond.get("value", None) is None:
                    lint.err("rule %r condition[%d]: %r requires a 'value'"
                             % (rid, j, ctype))
                elif ctype != "phase" and not isinstance(cond["value"], (int, float)):
                    lint.err("rule %r condition[%d]: %r needs a numeric 'value', got %r"
                             % (rid, j, ctype, cond["value"]))

        # ---- TRAPS 1 and 3 -------------------------------------------------
        for j, action in enumerate(actions):
            if not isinstance(action, dict):
                lint.err("rule %r action[%d] is not an object" % (rid, j))
                continue
            op = action.get("type", "override")
            param = action.get("param", "")
            if op not in action_ops:
                lint.err("rule %r action[%d]: unknown type %r — unknown ops match "
                         "no arm and are SILENTLY DROPPED. Valid: %s"
                         % (rid, j, op, ", ".join(sorted(action_ops))))
                continue
            if not param:
                lint.err("rule %r action[%d]: missing 'param'" % (rid, j))
                continue
            if param not in known:
                lint.err("rule %r action[%d]: parameter %r is never read by "
                         "get_param() — this action has no effect" % (rid, j, param))
                continue
            if not isinstance(action.get("value", None), (int, float)):
                lint.err("rule %r action[%d]: 'value' must be numeric, got %r"
                         % (rid, j, action.get("value")))
                continue

            if op in ("multiply", "add") and param not in declared:
                base = known[param]["default"]
                if op == "multiply":
                    effect = ("scales it to 0.0, switching the weight OFF "
                              "(0.0 * %s), not to %s" % (action["value"],
                              "%.4g" % (base * action["value"]) if base is not None else "?"))
                else:
                    effect = ("yields a bare %s, discarding the const default %s"
                              % (action["value"], base))
                lint.err("rule %r action[%d]: '%s' on %r, which this profile does "
                         "not declare in 'parameters'. _get_base_param_value "
                         "returns 0.0 for it (its %s lives only as a const), so "
                         "this %s. Fix: add \"%s\": %s to 'parameters'."
                         % (rid, j, op, param, "default of %s" % base
                            if base is not None else "value", effect, param, base))

    return lint


# ---------------------------------------------------------------------------

SELFTEST_CASES = [
    # (label, profile, expected_error_substring or None for "must be clean")
    ("clean profile", {
        "format": FORMAT_TAG, "version": 1, "profile_name": "clean",
        "parameters": {"WEIGHT_CONTESTED_OBJ": 9.0},
        "rules": [{"id": "r1", "priority": 1,
                   "conditions": [{"type": "round_gte", "value": 4}],
                   "actions": [{"type": "multiply", "param": "WEIGHT_CONTESTED_OBJ",
                                "value": 1.2}]}],
    }, None),
    ("silent-zero multiply", {
        "format": FORMAT_TAG, "version": 1, "profile_name": "trap1",
        "parameters": {},
        "rules": [{"id": "r1", "conditions": [{"type": "round_gte", "value": 4}],
                   "actions": [{"type": "multiply", "param": "WEIGHT_CONTESTED_OBJ",
                                "value": 1.2}]}],
    }, "switching the weight OFF"),
    ("silent-zero add", {
        "format": FORMAT_TAG, "version": 1, "profile_name": "trap1b",
        "parameters": {},
        "rules": [{"id": "r1", "conditions": [{"type": "round_gte", "value": 4}],
                   "actions": [{"type": "add", "param": "WEIGHT_CONTESTED_OBJ",
                                "value": 2.0}]}],
    }, "discarding the const default"),
    ("unknown condition type passes", {
        "format": FORMAT_TAG, "version": 1, "profile_name": "trap2",
        "parameters": {"WEIGHT_CONTESTED_OBJ": 8.0},
        "rules": [{"id": "r1", "conditions": [{"type": "round_gt", "value": 4}],
                   "actions": [{"type": "override", "param": "WEIGHT_CONTESTED_OBJ",
                                "value": 9.0}]}],
    }, "treated as MET"),
    ("unknown action op dropped", {
        "format": FORMAT_TAG, "version": 1, "profile_name": "trap3",
        "parameters": {"WEIGHT_CONTESTED_OBJ": 8.0},
        "rules": [{"id": "r1", "conditions": [{"type": "round_gte", "value": 4}],
                   "actions": [{"type": "scale", "param": "WEIGHT_CONTESTED_OBJ",
                                "value": 1.2}]}],
    }, "SILENTLY DROPPED"),
    ("dead vp condition", {
        "format": FORMAT_TAG, "version": 1, "profile_name": "trap4",
        "parameters": {"WEIGHT_CONTESTED_OBJ": 8.0},
        "rules": [{"id": "r1", "conditions": [{"type": "vp_behind"}],
                   "actions": [{"type": "override", "param": "WEIGHT_CONTESTED_OBJ",
                                "value": 9.0}]}],
    }, "vp_diff is always 0"),
    ("nonexistent parameter", {
        "format": FORMAT_TAG, "version": 1, "profile_name": "bogus",
        "parameters": {"TOTALLY_MADE_UP_WEIGHT": 3.0}, "rules": [],
    }, "never read by get_param()"),
    ("override on an undeclared param is fine", {
        "format": FORMAT_TAG, "version": 1, "profile_name": "ok-override",
        "parameters": {},
        "rules": [{"id": "r1", "conditions": [{"type": "round_gte", "value": 4}],
                   "actions": [{"type": "override", "param": "WEIGHT_CONTESTED_OBJ",
                                "value": 9.0}]}],
    }, None),
    ("duplicate rule ids", {
        "format": FORMAT_TAG, "version": 1, "profile_name": "dupes",
        "parameters": {}, "rules": [
            {"id": "r1", "conditions": [], "actions": []},
            {"id": "r1", "conditions": [], "actions": []}],
    }, "duplicate id"),
]


def selftest() -> int:
    manifest = build_manifest()
    fails = []
    for label, profile, expect in SELFTEST_CASES:
        lint = lint_profile(profile, "<selftest>", manifest, set())
        blob = " | ".join(lint.errors)
        if expect is None:
            if not lint.ok:
                fails.append("%s: expected clean, got %s" % (label, blob))
        elif expect not in blob:
            fails.append("%s: expected an error containing %r, got %r" % (label, expect, blob))
    # a profile that declares the parameter must NOT trip the silent-zero trap
    ok_case = {
        "format": FORMAT_TAG, "version": 1, "profile_name": "declared",
        "parameters": {"WEIGHT_CONTESTED_OBJ": 8.0},
        "rules": [{"id": "r1", "conditions": [{"type": "round_gte", "value": 4}],
                   "actions": [{"type": "multiply", "param": "WEIGHT_CONTESTED_OBJ",
                                "value": 1.2}]}],
    }
    if not lint_profile(ok_case, "<selftest>", manifest, set()).ok:
        fails.append("declaring the parameter should clear the silent-zero error")
    # ai_config.json supplying the base should also clear it
    if not lint_profile(SELFTEST_CASES[1][1], "<selftest>", manifest,
                        {"WEIGHT_CONTESTED_OBJ"}).ok:
        fails.append("an ai_config.json base should clear the silent-zero error")

    for f in fails:
        print("  FAIL %s" % f)
    print("selftest: %s (%d/%d checks failed)"
          % ("PASS" if not fails else "FAIL", len(fails), len(SELFTEST_CASES) + 2))
    return 1 if fails else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("profiles", nargs="*")
    ap.add_argument("--strict", action="store_true", help="treat warnings as failures")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--no-metadata", action="store_true",
                    help="skip format/version/profile_name checks (bench override files "
                         "are loaded directly by AIBenchmarkRunner, bypassing ProfileManager)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()
    if not args.profiles:
        ap.error("give at least one profile path (or --selftest)")

    manifest = build_manifest()
    config_params = load_config_params()
    lints = []
    for path in args.profiles:
        try:
            with open(path) as fh:
                data = json.load(fh)
        except (OSError, ValueError) as exc:
            lint = Lint(path)
            lint.err("could not read: %s" % exc)
            lints.append(lint)
            continue
        lint = lint_profile(data, path, manifest, config_params,
                            require_metadata=not args.no_metadata)
        if args.strict and lint.warnings:
            lint.errors.extend("(strict) " + w for w in lint.warnings)
            lint.warnings = []
        lints.append(lint)

    if args.json:
        print(json.dumps([l.as_dict() for l in lints], indent=2))
    else:
        for lint in lints:
            print("[%s] %s" % ("PASS" if lint.ok else "FAIL", lint.path))
            for e in lint.errors:
                print("   ERROR   %s" % e)
            for w in lint.warnings:
                print("   warning %s" % w)
        bad = [l.path for l in lints if not l.ok]
        print("\n%d profile(s) linted, %d failed%s"
              % (len(lints), len(bad), (": " + ", ".join(bad)) if bad else ""))
    return 1 if any(not l.ok for l in lints) else 0


if __name__ == "__main__":
    sys.exit(main())
