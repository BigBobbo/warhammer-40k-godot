#!/usr/bin/env python3
"""Map what the AI can currently SEE — the ceiling parameter search cannot pass.

Tuning 104 constants searches within a fixed feature space. If the space is
missing a consideration a strong player uses, no setting of those constants
recovers it: the search converges to the best point in a room whose walls it
cannot see. This tool draws the walls.

It answers four questions mechanically, from the M1 records:

  1. VOCABULARY — the distinct terms the AI's candidate scoring reports, per
     decision type. This is the AI's entire expressible feature set as far as
     any offline analysis can tell.

  2. DISCRIMINATION — of those terms, which actually VARY between the
     candidates of a single decision. A term that is constant across every
     option cannot have separated them; it is context, not a criterion.

  3. DECOMPOSITION — whether `score` is a genuine function of the reported
     terms, or merely a copy of one of them. If the latter, the record shows
     WHAT was chosen but not WHY, and every attribution built on it is
     guesswork. This is a defect detector, not a statistic.

  4. ATTRIBUTION — how many of the manifest's tunable parameters ever appear
     in a decision's `parameters_used`. Parameters that never surface cannot
     be credited or blamed by any analysis of this data, however many games
     are played.

What it deliberately does NOT do: say what is MISSING. Enumerating a set
cannot produce its complement — naming the consideration the AI never had
requires knowledge of 40k that is not in the data. That is the one job in
this pipeline where a language model beats its cheap baseline, and this
report is the reference such an audit must check its claims against, so that
"the AI never considers X" is a verifiable statement rather than an opinion.

Usage:
    python3 tools/ai_lab/feature_census.py bench_data/season_1
    python3 tools/ai_lab/feature_census.py <season> --json
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from build_index import find_records, load_record, SCHEMA  # noqa: E402
from params_manifest import build_manifest  # noqa: E402

NUM = (int, float)


def census(paths: list[str]) -> dict:
    vocab: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    varies: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    decisions_seen: collections.Counter = collections.Counter()
    multi_cand: collections.Counter = collections.Counter()
    # score == some single breakdown term?
    mirrors: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    scored: collections.Counter = collections.Counter()
    params_used: collections.Counter = collections.Counter()
    phases_with_actions: set = set()
    phases_with_records: set = set()
    games = 0

    for p in paths:
        try:
            rec = load_record(p)
        except (OSError, ValueError):
            continue
        if rec.get("schema") != SCHEMA:
            continue
        games += 1

        for entry in rec.get("action_log") or []:
            phases_with_actions.add(entry.get("phase"))

        for batch in rec.get("decisions") or []:
            phases_with_records.add(batch.get("phase_name"))
            for r in batch.get("records") or []:
                dt = r.get("decision_type", "?")
                decisions_seen[dt] += 1
                for k in (r.get("parameters_used") or {}):
                    params_used[k] += 1

                cands = r.get("candidates") or []
                if len(cands) > 1:
                    multi_cand[dt] += 1

                # collect per-term values across this decision's candidates
                per_term: dict[str, list] = collections.defaultdict(list)
                for c in cands:
                    for k, v in ((c or {}).get("score_breakdown") or {}).items():
                        vocab[dt][k] += 1
                        per_term[k].append(v)

                # a term only discriminates if it differs between the options
                if len(cands) > 1:
                    for k, vals in per_term.items():
                        if len(vals) > 1 and len(set(map(repr, vals))) > 1:
                            varies[dt][k] += 1

                # is `score` just a copy of one reported term?
                for c in cands:
                    s = (c or {}).get("score")
                    if not isinstance(s, NUM):
                        continue
                    scored[dt] += 1
                    for k, v in ((c or {}).get("score_breakdown") or {}).items():
                        if isinstance(v, NUM) and abs(float(v) - float(s)) < 1e-9:
                            mirrors[dt][k] += 1

    return {
        "games": games,
        "vocab": {k: dict(v) for k, v in vocab.items()},
        "varies": {k: dict(v) for k, v in varies.items()},
        "decisions_seen": dict(decisions_seen),
        "multi_cand": dict(multi_cand),
        "mirrors": {k: dict(v) for k, v in mirrors.items()},
        "scored": dict(scored),
        "params_used": dict(params_used),
        "phases_with_actions": sorted(x for x in phases_with_actions if x is not None),
        "phases_with_records": sorted(x for x in phases_with_records if x),
    }


def report(c: dict, manifest: dict) -> None:
    known = manifest["parameters"]
    total_decisions = sum(c["decisions_seen"].values())

    print("=" * 74)
    print("FEATURE CENSUS — %d game(s), %d decision records" % (c["games"], total_decisions))
    print("=" * 74)

    print("\n1. VOCABULARY — every term the AI's scoring reports")
    print("   (this is the whole expressible feature space, as far as the data shows)\n")
    all_terms = set()
    for dt in sorted(c["vocab"]):
        terms = c["vocab"][dt]
        var = c["varies"].get(dt, {})
        multi = c["multi_cand"].get(dt, 0)
        all_terms |= set(terms)
        print("   %s  (%d decisions, %d with >1 candidate)"
              % (dt, c["decisions_seen"].get(dt, 0), multi))
        for term in sorted(terms, key=lambda t: -terms[t]):
            v = var.get(term, 0)
            pct = (100.0 * v / multi) if multi else 0.0
            note = ""
            if multi and pct == 0.0:
                note = "   <- CONSTANT across options: cannot have discriminated"
            elif multi and pct < 25.0:
                note = "   <- rarely varies"
            print("      %-24s seen %5d   varies in %5.1f%% of choices%s"
                  % (term, terms[term], pct, note))
        print()
    print("   TOTAL DISTINCT TERMS ACROSS THE WHOLE AI: %d" % len(all_terms))

    print("\n2. DECOMPOSITION — does `score` explain itself?\n")
    degraded = []
    for dt in sorted(c["scored"]):
        n = c["scored"][dt]
        hits = c["mirrors"].get(dt, {})
        top = max(hits.items(), key=lambda kv: kv[1]) if hits else None
        if top and n and top[1] / n > 0.95:
            degraded.append((dt, top[0]))
            print("   %-10s score == %s in %.0f%% of candidates" % (dt, top[0], 100.0 * top[1] / n))
            print("              -> the other terms are ANNOTATION, not components. This record")
            print("                 shows what was chosen, not why. Attribution built on it is")
            print("                 guesswork until score_breakdown is a real decomposition.")
        else:
            print("   %-10s score is not a copy of any single reported term" % dt)

    print("\n3. ATTRIBUTION — how much of the tunable surface is even visible\n")
    used = set(c["params_used"])
    known_used = used & set(known)
    unknown_used = used - set(known)
    print("   tunable parameters in the manifest ........ %d" % len(known))
    print("   ever named in a decision record ........... %d" % len(known_used))
    print("   NEVER named (unattributable from this data) %d" % (len(known) - len(known_used)))
    if unknown_used:
        print("   recorded under names not in the manifest .. %d  %s"
              % (len(unknown_used), sorted(unknown_used)))
    if known_used:
        print("\n   attributable parameters:")
        for p in sorted(known_used, key=lambda x: -c["params_used"][x]):
            print("      %-40s in %d decisions" % (p, c["params_used"][p]))

    print("\n4. PHASE COVERAGE — where decisions are recorded at all\n")
    print("   phases the AI acted in ......... %s" % (c["phases_with_actions"] or "n/a"))
    print("   phases with decision records ... %s" % (c["phases_with_records"] or "n/a"))
    print("   -> decision types recorded: %s" % ", ".join(sorted(c["decisions_seen"])))

    print("\n" + "=" * 74)
    print("WHAT THIS BOUNDS")
    print("=" * 74)
    print("   Parameter search moves within the %d terms above. It cannot add a term."
          % len(all_terms))
    print("   %d of %d tunable parameters never surface in the record, so no amount of"
          % (len(known) - len(known_used), len(known)))
    print("   games makes their effect attributable offline.")
    if degraded:
        print("   %d decision type(s) report a score that is a copy of one term, so their"
              % len(degraded))
        print("   candidate reasoning is not recoverable from the data at all.")
    print("\n   An expressiveness audit (human or LLM) should treat this list as the")
    print("   reference: a claim that the AI 'never considers X' is only credible if X")
    print("   is absent from the vocabulary above AND from params_manifest.py.")
    print("=" * 74)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("season_dir")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    paths = find_records(args.season_dir)
    if not paths:
        raise SystemExit("no *.record.json[.gz] under %s" % args.season_dir)
    c = census(paths)
    manifest = build_manifest()
    if args.json:
        c["manifest_param_count"] = len(manifest["parameters"])
        print(json.dumps(c, indent=2, sort_keys=True))
    else:
        report(c, manifest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
