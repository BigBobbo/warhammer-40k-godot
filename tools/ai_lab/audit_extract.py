#!/usr/bin/env python3
"""Build an expressiveness-audit dossier from a season of game records.

The audit this feeds asks ONE question, and deliberately not the obvious one:

    NOT  "was this a good move?"      — unfalsifiable at +/-8 VP paired noise,
                                        and judging it needs 36 games per call
    BUT  "is this even EXPRESSIBLE?"  — a coverage question about the search
                                        space, checkable against the manifest,
                                        costing zero games

Parameter search moves within a fixed feature space. feature_census.py measures
that space at 12 distinct scoring terms. If a consideration a strong player uses
is absent from those 12, no setting of the 104 constants recovers it — the
search converges to the best point in a room whose walls it cannot see. The
audit's job is to name walls; this tool assembles the evidence it reasons over.

A raw record is ~485 KB of JSON, so this does NOT dump games. It selects the
decisions where a missing consideration would actually show up:

  * every multi-candidate SHOOTING choice — scoring there is expected damage
    alone, so any consideration beyond raw damage is by construction absent
  * the highest-regret decisions — where something overrode the AI's own score
  * decisions in the round that swung most against the deciding player
  * multi-candidate charge and fight choices — small populations, so all of them

Output is compact text (or JSON) carrying, for each surfaced decision, the full
candidate list with descriptions, scores and reported breakdown, plus the game's
VP timeline for context.

Usage:
    python3 tools/ai_lab/audit_extract.py bench_data/season_1
    python3 tools/ai_lab/audit_extract.py <season> --max-games 3 --per-type 6
    python3 tools/ai_lab/audit_extract.py <season> --json > dossier.json
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from build_index import find_records, load_record, SCHEMA, _num, _int  # noqa: E402


def decision_view(batch_idx, rec_idx, batch, r) -> dict:
    cands = r.get("candidates") or []
    scores = [_num((c or {}).get("score")) for c in cands]
    scores = [s for s in scores if s is not None]
    ci = _int(r.get("chosen_index"), -1)
    chosen = _num((cands[ci] or {}).get("score")) if 0 <= ci < len(cands) else None
    best = max(scores) if scores else None
    return {
        "cite": "batch %d / record %d" % (batch_idx, rec_idx),
        "round": _int(batch.get("round"), 0),
        "phase": batch.get("phase_name", ""),
        "player": _int(batch.get("player"), 0),
        "decision_type": r.get("decision_type", ""),
        "unit": r.get("unit_name", ""),
        "unit_id": r.get("unit_id", ""),
        "chosen_index": ci,
        "n_candidates": len(cands),
        "regret": (None if (best is None or chosen is None) else round(best - chosen, 4)),
        "parameters_used": r.get("parameters_used") or {},
        "candidates": [{
            "i": i,
            "taken": (i == ci),
            "description": (c or {}).get("description", ""),
            "score": (c or {}).get("score"),
            "breakdown": (c or {}).get("score_breakdown") or {},
        } for i, c in enumerate(cands)],
    }


def worst_round_for(vp_events: list, player: int):
    """The round in which the OPPONENT out-scored this player by the most."""
    per = collections.defaultdict(lambda: collections.defaultdict(int))
    for e in vp_events:
        per[_int(e.get("round"), 0)][_int(e.get("player"), 0)] += _int(e.get("points"), 0)
    worst, worst_swing = None, None
    for rnd, byp in per.items():
        swing = byp.get(3 - player, 0) - byp.get(player, 0)
        if worst_swing is None or swing > worst_swing:
            worst, worst_swing = rnd, swing
    return worst, worst_swing


def build_dossier(rec: dict, per_type: int) -> dict:
    prov = rec.get("provenance") or {}
    out = rec.get("outcome") or {}
    vp_events = rec.get("vp_events") or []

    views = []
    for bi, batch in enumerate(rec.get("decisions") or []):
        for ri, r in enumerate(batch.get("records") or []):
            views.append(decision_view(bi, ri, batch, r))

    # The losing player is where a missing consideration is most likely to bite.
    winner = _int(out.get("winner"), 0)
    loser = 3 - winner if winner in (1, 2) else 1
    worst_round, worst_swing = worst_round_for(vp_events, loser)

    def pick(pred, key=None, limit=per_type):
        sel = [v for v in views if pred(v)]
        if key:
            sel.sort(key=key)
        return sel[:limit]

    selections = {
        # scoring here is expected damage alone, so anything else is absent by construction
        "shooting_with_real_choice": pick(
            lambda v: v["decision_type"] == "shooting" and v["n_candidates"] > 1,
            key=lambda v: -v["n_candidates"]),
        "highest_regret": pick(
            lambda v: v["regret"] is not None and v["regret"] > 0,
            key=lambda v: -v["regret"]),
        "in_worst_round_for_loser": pick(
            lambda v: v["round"] == worst_round and v["player"] == loser
            and v["n_candidates"] > 1,
            key=lambda v: -v["n_candidates"]),
        "charge_with_real_choice": pick(
            lambda v: v["decision_type"] == "charge" and v["n_candidates"] > 1,
            key=lambda v: -v["n_candidates"]),
        "fight_with_real_choice": pick(
            lambda v: v["decision_type"] == "fight" and v["n_candidates"] > 1,
            key=lambda v: -v["n_candidates"]),
    }

    vp_by_round = collections.defaultdict(lambda: {1: 0, 2: 0})
    for e in vp_events:
        vp_by_round[_int(e.get("round"), 0)][_int(e.get("player"), 0)] += _int(e.get("points"), 0)

    return {
        "game_id": rec.get("game_id", ""),
        "fixture": prov.get("fixture", ""),
        "seed": prov.get("seed"),
        "git_sha": prov.get("git_sha", ""),
        "difficulty": (prov.get("difficulty") or {}).get("1"),
        "status": out.get("status", ""),
        "winner": winner,
        "loser_focus": loser,
        "margin_p2_minus_p1": out.get("vp_diff_p2_minus_p1"),
        "vp": out.get("vp"),
        "worst_round_for_loser": worst_round,
        "worst_round_swing": worst_swing,
        "vp_by_round": {str(k): dict(v) for k, v in sorted(vp_by_round.items())},
        "vp_events": [{"round": _int(e.get("round"), 0), "player": _int(e.get("player"), 0),
                       "points": _int(e.get("points"), 0), "reason": e.get("reason", "")}
                      for e in vp_events],
        "decision_totals": dict(collections.Counter(v["decision_type"] for v in views)),
        "selections": selections,
    }


def render(d: dict) -> str:
    L = []
    L.append("=" * 74)
    L.append("GAME %s  [%s seed=%s %s]" % (d["game_id"], d["fixture"], d["seed"], d["git_sha"]))
    L.append("  status=%s  winner=P%s  margin(P2-P1)=%s  vp=%s"
             % (d["status"], d["winner"], d["margin_p2_minus_p1"],
                json.dumps(d.get("vp") or {}, sort_keys=True)))
    L.append("  decisions recorded: %s" % d["decision_totals"])
    L.append("  VP by round: %s" % json.dumps(d["vp_by_round"]))
    L.append("  focus player (lost): P%s   worst round for them: %s (swing %s)"
             % (d["loser_focus"], d["worst_round_for_loser"], d["worst_round_swing"]))
    L.append("")
    L.append("  VP events:")
    for e in d["vp_events"]:
        L.append("    r%d P%d +%d  %s" % (e["round"], e["player"], e["points"], e["reason"]))

    for name, sel in d["selections"].items():
        if not sel:
            continue
        L.append("")
        L.append("-" * 74)
        L.append("  %s  (%d shown)" % (name.upper().replace("_", " "), len(sel)))
        L.append("-" * 74)
        for v in sel:
            L.append("   [%s] r%d %s P%d  %s (%s)  chose #%d of %d  regret=%s"
                     % (v["cite"], v["round"], v["phase"], v["player"], v["unit"],
                        v["decision_type"], v["chosen_index"], v["n_candidates"], v["regret"]))
            if v["parameters_used"]:
                L.append("        params: %s" % json.dumps(v["parameters_used"], sort_keys=True))
            for c in v["candidates"]:
                mark = "->" if c["taken"] else "  "
                score = c["score"]
                score_s = ("%.3f" % score) if isinstance(score, (int, float)) else str(score)
                bd = {k: (round(x, 3) if isinstance(x, (int, float)) else x)
                      for k, x in c["breakdown"].items()}
                L.append("      %s #%d %-46s score=%-9s %s"
                         % (mark, c["i"], c["description"][:46], score_s,
                            json.dumps(bd, sort_keys=True)))
            L.append("")
    return "\n".join(L)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("season_dir")
    ap.add_argument("--max-games", type=int, default=3)
    ap.add_argument("--per-type", type=int, default=5)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    paths = find_records(args.season_dir)
    if not paths:
        raise SystemExit("no *.record.json[.gz] under %s" % args.season_dir)

    dossiers = []
    for p in paths[: args.max_games]:
        try:
            rec = load_record(p)
        except (OSError, ValueError):
            continue
        if rec.get("schema") != SCHEMA:
            continue
        dossiers.append(build_dossier(rec, args.per_type))

    if args.json:
        print(json.dumps(dossiers, indent=2, sort_keys=True))
    else:
        for d in dossiers:
            print(render(d))
        print("\n%d game(s) of %d in the season" % (len(dossiers), len(paths)))
        print("Audit rule: a claim that the AI 'never considers X' is only credible if X is")
        print("absent from feature_census.py's vocabulary AND from params_manifest.py.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
