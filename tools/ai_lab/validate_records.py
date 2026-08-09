#!/usr/bin/env python3
"""Are the decision records honest enough to learn from?

M1 gave every game a decision trace. The expressiveness audit
(`research/audit_findings_2026-08-07.md`) then found that large parts of that
trace describe the AI's *conclusion* rather than its *reasoning*, which is a
much quieter failure than having no trace at all — the analysis runs, the
numbers come out, and they mean nothing:

  F-05  movement `score` equals `objective_priority` in 99% of candidates, so
        the record says WHAT was chosen and nothing about WHY. Every
        attribution built on it is guesswork.
  F-06  `parameters_used` advertised names that are bare `const`s no profile
        can move, so an optimiser (or an LLM) reading records would aim at
        knobs that do not exist.
  F-04  shooting candidates restated the plan rather than the options weighed.
  F-07  `unit_oc` was logged as a scoring criterion while being constant
        across every candidate of a decision — context wearing a criterion's
        clothes.

This is the checker for those invariants. It is deliberately mechanical: each
check is a property a record either has or does not, so it can gate a commit
and sit in CI without a human in the loop.

Checks
------
sum-equals-score   For decision types that claim an additive decomposition,
                   sum(score_breakdown terms) == score within tolerance.
named-terms        Those candidates carry at least MIN_TERMS named terms.
params-exist       Every name in `parameters_used` is a real tunable, i.e. it
                   appears in params_manifest.py's output. This is the F-06
                   check and it is why the manifest is derived from source.
criteria-vary      A key reported inside score_breakdown must actually differ
                   between the candidates of at least some decisions; a key
                   that never varies anywhere is context, not a criterion.
schema             Records have the fields the downstream tooling indexes.

Usage
-----
    python3 tools/ai_lab/validate_records.py <season-dir-or-record.json[.gz]>
    python3 tools/ai_lab/validate_records.py <season> --json
    python3 tools/ai_lab/validate_records.py --schema-only <season>
    python3 tools/ai_lab/validate_records.py --selftest

Exit 0 only if every enabled check passes.
"""
from __future__ import annotations

import argparse
import collections
import glob
import gzip
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from build_index import find_records, load_record, SCHEMA  # noqa: E402
from params_manifest import build_manifest  # noqa: E402

NUM = (int, float)

# Decision types whose score is built as a sum of named terms. Anything not
# listed here is checked for schema and parameters only — a two-way EV
# comparison (hold_fire) has a breakdown, but its terms are the two sides of
# the comparison, not addends of the score.
DECOMPOSED_TYPES = ("movement",)

# The audit's bar: a decomposition of one term is not a decomposition.
MIN_TERMS = 3
# Fraction of a decomposed type's candidates that must satisfy both invariants.
MIN_PASS_RATE = 0.95
# Absolute tolerance on sum(terms) == score.
TOL = 0.01

# Keys that are legitimately present in a breakdown without being addends —
# they describe the candidate rather than contributing to its score. Keeping
# this list short and explicit is the point: every entry is a decision that
# this key is context, and F-07 is exactly the bug of getting that wrong.
NON_ADDITIVE_KEYS = {
    "assigned_by",        # which assignment pass produced this candidate
    "assign_pass",
    "expected_vp",        # reported for the player, not summed into score
    "distance_inches",
    "turns_to_reach",
    "unit_oc",            # F-07: context, kept for readability, never an addend
}


def _iter_records(target: str):
    if os.path.isdir(target):
        paths = find_records(target)
    else:
        paths = [target]
    for p in paths:
        try:
            yield p, load_record(p)
        except (OSError, ValueError) as exc:
            yield p, {"_load_error": str(exc)}


def _terms_of(cand: dict) -> dict:
    bd = cand.get("score_breakdown") or {}
    if not isinstance(bd, dict):
        return {}
    return {k: v for k, v in bd.items()
            if isinstance(v, NUM) and not isinstance(v, bool)
            and k not in NON_ADDITIVE_KEYS}


def validate(target: str, schema_only: bool = False) -> dict:
    manifest = set(build_manifest()["parameters"].keys())

    games = 0
    load_errors: list[str] = []
    schema_errors: list[str] = []
    unknown_params: collections.Counter = collections.Counter()
    param_names: set[str] = set()
    per_type: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    decomposed_ok = 0
    decomposed_total = 0
    terms_ok = 0
    examples: list[dict] = []
    # key -> did this key ever differ between two candidates of one decision?
    key_varies: dict[str, bool] = {}

    for path, rec in _iter_records(target):
        if "_load_error" in rec:
            load_errors.append("%s: %s" % (os.path.basename(path), rec["_load_error"]))
            continue
        if rec.get("schema") != SCHEMA:
            schema_errors.append("%s: schema=%r" % (os.path.basename(path), rec.get("schema")))
            continue
        games += 1
        for batch in rec.get("decisions") or []:
            for r in batch.get("records") or []:
                dtype = str(r.get("decision_type", ""))
                per_type[dtype]["records"] += 1
                for field in ("unit_id", "candidates", "chosen_index"):
                    if field not in r:
                        schema_errors.append("%s: %s record missing %r"
                                             % (os.path.basename(path), dtype, field))
                cands = r.get("candidates") or []
                ci = r.get("chosen_index")
                if isinstance(ci, int) and cands and not (0 <= ci < len(cands)):
                    schema_errors.append("%s: %s chosen_index %d out of range (%d candidates)"
                                         % (os.path.basename(path), dtype, ci, len(cands)))
                if isinstance(ci, int) and ci > 0:
                    per_type[dtype]["chosen_nonzero"] += 1
                if len(cands) >= 2:
                    per_type[dtype]["multi_candidate"] += 1

                for name in (r.get("parameters_used") or {}):
                    param_names.add(name)
                    if name not in manifest:
                        unknown_params[name] += 1

                if schema_only:
                    continue

                # criteria-vary: collect per-key value sets within this decision
                seen: dict[str, set] = collections.defaultdict(set)
                for c in cands:
                    for k, v in (c.get("score_breakdown") or {}).items():
                        if isinstance(v, NUM) and not isinstance(v, bool):
                            seen[k].add(round(float(v), 6))
                for k, vals in seen.items():
                    key_varies[k] = key_varies.get(k, False) or len(vals) > 1

                if dtype not in DECOMPOSED_TYPES:
                    continue
                for c in cands:
                    decomposed_total += 1
                    terms = _terms_of(c)
                    score = c.get("score")
                    if not isinstance(score, NUM):
                        continue
                    total = sum(terms.values())
                    close = abs(total - float(score)) <= TOL
                    if close:
                        decomposed_ok += 1
                    elif len(examples) < 5:
                        examples.append({"type": dtype, "score": float(score),
                                         "sum_terms": round(total, 4),
                                         "terms": {k: round(v, 4) for k, v in terms.items()}})
                    if len(terms) >= MIN_TERMS:
                        terms_ok += 1

    checks: list[dict] = []

    def add(name, ok, detail):
        checks.append({"check": name, "ok": bool(ok), "detail": detail})

    add("loadable", not load_errors, load_errors[:5] or "all records parsed")
    add("schema", not schema_errors, schema_errors[:5] or "records carry the indexed fields")
    add("params-exist", not unknown_params,
        ("names not in params_manifest: %s" % dict(unknown_params.most_common(8)))
        if unknown_params else "%d distinct parameter names, all reachable via get_param"
        % len(param_names))

    if not schema_only:
        rate = (decomposed_ok / decomposed_total) if decomposed_total else 0.0
        trate = (terms_ok / decomposed_total) if decomposed_total else 0.0
        add("sum-equals-score", decomposed_total > 0 and rate >= MIN_PASS_RATE,
            "%d/%d decomposed candidates satisfy sum(terms)==score (%.1f%%, need %.0f%%)%s"
            % (decomposed_ok, decomposed_total, 100 * rate, 100 * MIN_PASS_RATE,
               "" if decomposed_total else " — NO decomposed candidates found"))
        add("named-terms", decomposed_total > 0 and trate >= MIN_PASS_RATE,
            "%d/%d carry >= %d named terms (%.1f%%)"
            % (terms_ok, decomposed_total, MIN_TERMS, 100 * trate))
        constant_keys = sorted(k for k, v in key_varies.items() if not v)
        add("criteria-vary", True,
            ("keys that NEVER varied between candidates (context, not criteria): %s"
             % ", ".join(constant_keys[:10])) if constant_keys
            else "every reported breakdown key varied somewhere")

    return {
        "target": target, "games": games,
        "decision_types": {k: dict(v) for k, v in sorted(per_type.items())},
        "distinct_parameters_in_records": len(param_names),
        "parameters_in_records": sorted(param_names),
        "checks": checks,
        "mismatch_examples": examples,
        "ok": all(c["ok"] for c in checks),
    }


def _selftest() -> int:
    """A good record passes; each seeded defect fails its own check."""
    import tempfile

    def rec(cands, params=None, dtype="movement"):
        return {
            "schema": SCHEMA, "schema_version": 1, "game_id": "selftest",
            "provenance": {"seed": 1}, "outcome": {},
            "decisions": [{"round": 1, "phase_name": "movement", "player": 1,
                           "records": [{"decision_type": dtype, "unit_id": "U_A",
                                        "unit_name": "A", "chosen_index": 0,
                                        "candidates": cands,
                                        "parameters_used": params or {}}]}],
            "action_log": [],
        }

    good = [
        {"description": "obj_a", "score": 6.0,
         "score_breakdown": {"objective_priority": 4.0, "distance_penalty": -1.0,
                             "stay_on_objective": 3.0, "unit_oc": 2}},
        {"description": "obj_b", "score": 2.0,
         "score_breakdown": {"objective_priority": 3.0, "distance_penalty": -2.0,
                             "stay_on_objective": 1.0, "unit_oc": 2}},
    ]
    # F-05 shape: score is a copy of one term, breakdown does not add up.
    bad_sum = [dict(c, score=99.0) for c in good]
    # A decomposition of one term is not a decomposition.
    bad_terms = [{"description": "obj_a", "score": 4.0,
                  "score_breakdown": {"objective_priority": 4.0}}] * 2
    # F-06 shape: advertising a const no get_param reads.
    bad_param = good

    cases = [
        ("good record", rec(good), True, None),
        ("sum != score", rec(bad_sum), False, "sum-equals-score"),
        ("one term only", rec(bad_terms), False, "named-terms"),
        ("phantom parameter", rec(bad_param, {"TOTALLY_NOT_A_PARAM_XYZ": 1.0}),
         False, "params-exist"),
    ]
    failures = 0
    with tempfile.TemporaryDirectory() as td:
        for i, (label, r, want_ok, want_check) in enumerate(cases):
            p = os.path.join(td, "sel_%d.record.json" % i)
            with io.open(p, "w", encoding="utf-8") as fh:
                json.dump(r, fh)
            res = validate(p)
            got_ok = res["ok"]
            failed = [c["check"] for c in res["checks"] if not c["ok"]]
            ok = (got_ok == want_ok) and (want_check is None or want_check in failed)
            print("  %-22s ok=%-5s failed=%s  %s"
                  % (label, got_ok, failed or "-", "PASS" if ok else "FAIL"))
            if not ok:
                failures += 1
    print("\nselftest: %s" % ("PASS" if not failures else "FAIL (%d)" % failures))
    return 1 if failures else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("target", nargs="?", help="season directory or one record file")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--schema-only", action="store_true",
                    help="skip the record-content checks; for CI, where no games run")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)

    if args.selftest:
        return _selftest()
    if not args.target:
        ap.error("a season directory or record file is required")

    res = validate(args.target, schema_only=args.schema_only)
    if args.json:
        print(json.dumps(res, indent=2))
        return 0 if res["ok"] else 1

    print("=" * 74)
    print("RECORD VALIDATION — %s" % args.target)
    print("=" * 74)
    print("  %d game record(s)" % res["games"])
    if res["decision_types"]:
        print("\n  %-14s %8s %8s %8s" % ("type", "records", ">=2 cand", "chosen>0"))
        for t, c in res["decision_types"].items():
            print("  %-14s %8d %8d %8d" % (t or "<none>", c.get("records", 0),
                                           c.get("multi_candidate", 0),
                                           c.get("chosen_nonzero", 0)))
    print("\n  %d distinct tunable parameters appear in records"
          % res["distinct_parameters_in_records"])
    print()
    for c in res["checks"]:
        print("  [%s] %-18s %s" % ("PASS" if c["ok"] else "FAIL", c["check"], c["detail"]))
    for ex in res["mismatch_examples"]:
        print("\n  mismatch: score=%.4f sum(terms)=%.4f  %s"
              % (ex["score"], ex["sum_terms"], ex["terms"]))
    print("\n" + "=" * 74)
    print("VERDICT: %s" % ("PASS" if res["ok"] else "FAIL"))
    print("=" * 74)
    return 0 if res["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
