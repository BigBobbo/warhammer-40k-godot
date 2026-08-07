#!/usr/bin/env python3
"""M1 — turn a directory of game records into a queryable season.

Input:  `wh40k_ai_game_record` files (.json or .json.gz) written by
        AIBenchmarkRunner._write_game_record — one per benchmark game.
Output: three flat Parquet tables + a DuckDB database with joining views.

    games       one row per game: outcome, provenance, hashes
    decisions   one row per decision record: what the AI considered, how it
                scored the options, which it took, and the regret against its
                own best-scoring candidate
    vp_events   one row per VP award: the intermediate reward signal

Why flatten at all: a record is deeply nested (batch -> record -> candidate ->
score_breakdown) and a season is thousands of files. Flattening once makes
"which decisions preceded a losing game" a one-line query instead of a
bespoke script every time.

Why DuckDB: no server, no schema migrations, reads Parquet directly, and a
season directory stays the unit of retention. It is an optional dependency —
without it you still get the Parquet/CSV tables.

Usage:
    python3 tools/ai_lab/build_index.py bench_data/season_1
    python3 tools/ai_lab/build_index.py bench_data/season_1 --out /tmp/idx
    python3 tools/ai_lab/build_index.py --selftest
"""
from __future__ import annotations

import argparse
import glob
import gzip
import json
import os
import shutil
import sys
import tempfile

SCHEMA = "wh40k_ai_game_record"

try:
    import duckdb  # type: ignore
except ImportError:  # pragma: no cover - exercised on machines without duckdb
    duckdb = None


# ---------------------------------------------------------------------------
# reading
# ---------------------------------------------------------------------------

def load_record(path: str) -> dict:
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt") as fh:
        return json.load(fh)


def find_records(season_dir: str) -> list[str]:
    out = []
    for pat in ("*.record.json", "*.record.json.gz"):
        out.extend(glob.glob(os.path.join(season_dir, "**", pat), recursive=True))
    return sorted(out)


# ---------------------------------------------------------------------------
# flattening
# ---------------------------------------------------------------------------

def _num(x, default=None):
    try:
        return float(x)
    except (TypeError, ValueError):
        return default


def _int(x, default=0):
    """Coerce to int, treating only None/missing/unparseable as absent.

    Deliberately NOT `int(x or default)`: zero is falsy in Python, and zero is
    a perfectly legitimate value here — chosen_index 0 is "the AI took its
    first candidate", difficulty 0 is EASY, seed 0 is a seed. The `or` form
    silently rewrote every one of those to the default, which nulled the whole
    regret column for any decision that picked its top option.
    """
    if x is None:
        return default
    try:
        return int(x)
    except (TypeError, ValueError):
        return default


def game_row(rec: dict, path: str) -> dict:
    prov = rec.get("provenance") or {}
    out = rec.get("outcome") or {}
    vp = out.get("vp") or {}
    p1 = vp.get("player1") or {}
    p2 = vp.get("player2") or {}
    return {
        "game_id": rec.get("game_id", ""),
        "path": path,
        "schema_version": _int(rec.get("schema_version"), 0),
        # provenance — the corrupt-fixture episode is why these are not optional
        "git_sha": prov.get("git_sha", ""),
        "engine": prov.get("engine", ""),
        "fixture": prov.get("fixture", ""),
        "fixture_sha256": prov.get("fixture_sha256", ""),
        "p1_profile_path": (prov.get("p1_profile") or {}).get("path", ""),
        "p1_profile_sha256": (prov.get("p1_profile") or {}).get("sha256", ""),
        "p2_profile_path": (prov.get("p2_profile") or {}).get("path", ""),
        "p2_profile_sha256": (prov.get("p2_profile") or {}).get("sha256", ""),
        "arm": prov.get("arm", ""),
        "seed": _int(prov.get("seed"), -1),
        "difficulty": _int((prov.get("difficulty") or {}).get("1"), -1),
        "time_scale": _num(prov.get("time_scale"), 0.0),
        # outcome
        "status": out.get("status", ""),
        "note": out.get("note", ""),
        "winner": _int(out.get("winner"), 0),
        "vp_diff_p2_minus_p1": _int(out.get("vp_diff_p2_minus_p1"), 0),
        "vp_p1_total": _int(p1.get("total"), 0),
        "vp_p1_primary": _int(p1.get("primary"), 0),
        "vp_p1_secondary": _int(p1.get("secondary"), 0),
        "vp_p2_total": _int(p2.get("total"), 0),
        "vp_p2_primary": _int(p2.get("primary"), 0),
        "vp_p2_secondary": _int(p2.get("secondary"), 0),
        "battle_round": _int(out.get("battle_round"), 0),
        "actions_taken": _int(out.get("actions_taken"), 0),
        "wall_seconds": _num(out.get("wall_seconds"), 0.0),
        # data-quality flags — a game with dropped batches is a biased sample
        "decision_batches_total": _int(rec.get("decision_batches_total"), 0),
        "decision_batches_dropped": _int(rec.get("decision_batches_dropped"), 0),
        "n_decisions": sum(len(b.get("records") or []) for b in (rec.get("decisions") or [])),
        "n_vp_events": len(rec.get("vp_events") or []),
    }


def decision_rows(rec: dict) -> list[dict]:
    """One row per decision record.

    `regret_vs_own_best` is the gap between the score of the candidate the AI
    took and the best score it assigned to any candidate. It is nonzero when
    difficulty noise or a coordination override deflected the choice away from
    the heuristic's own opinion. It measures deviation from the HEURISTIC, not
    from truth — a useful mining signal, not a reward.
    """
    game_id = rec.get("game_id", "")
    rows = []
    for batch_idx, batch in enumerate(rec.get("decisions") or []):
        for rec_idx, r in enumerate(batch.get("records") or []):
            cands = r.get("candidates") or []
            scores = [_num((c or {}).get("score")) for c in cands]
            scores = [s for s in scores if s is not None]
            chosen_index = _int(r.get("chosen_index"), -1)
            chosen_score = None
            if 0 <= chosen_index < len(cands):
                chosen_score = _num((cands[chosen_index] or {}).get("score"))
            best_score = max(scores) if scores else None
            ctx = r.get("context") or {}
            rows.append({
                "game_id": game_id,
                "batch_index": batch_idx,
                "record_index": rec_idx,
                "round": _int(batch.get("round"), 0),
                "phase_name": batch.get("phase_name", ""),
                "player": _int(batch.get("player"), 0),
                "decision_type": r.get("decision_type", ""),
                "unit_id": r.get("unit_id", ""),
                "unit_name": r.get("unit_name", ""),
                "difficulty_name": r.get("difficulty", ""),
                "n_candidates": len(cands),
                "chosen_index": chosen_index,
                "chosen_score": chosen_score,
                "best_score": best_score,
                "regret_vs_own_best": (
                    None if (best_score is None or chosen_score is None)
                    else round(best_score - chosen_score, 6)),
                "chosen_description": (
                    (cands[chosen_index] or {}).get("description", "")
                    if 0 <= chosen_index < len(cands) else ""),
                # kept as JSON text: the key set varies per decision type, so a
                # column-per-parameter schema would be sparse and unstable
                "parameters_used": json.dumps(r.get("parameters_used") or {}, sort_keys=True),
                "context": json.dumps(ctx, sort_keys=True),
                "context_phase": ctx.get("phase"),
                "context_round": ctx.get("round"),
            })
    return rows


def vp_rows(rec: dict) -> list[dict]:
    game_id = rec.get("game_id", "")
    return [{
        "game_id": game_id,
        "seq": i,
        "round": _int(e.get("round"), 0),
        "phase": _int(e.get("phase"), -1),
        "player": _int(e.get("player"), 0),
        "points": _int(e.get("points"), 0),
        "reason": e.get("reason", ""),
        "wall_seconds": _num(e.get("wall_seconds"), 0.0),
    } for i, e in enumerate(rec.get("vp_events") or [])]


# ---------------------------------------------------------------------------
# writing
# ---------------------------------------------------------------------------

VIEWS = {
    # Every decision joined to how the game it belonged to turned out. This is
    # the join that did not exist before M1: the AI's reasoning and the
    # consequence of that reasoning lived in different places (one in RAM and
    # discarded at quit, the other in a result JSON).
    "decision_outcomes": """
        SELECT d.*, g.fixture, g.arm, g.seed, g.status, g.winner,
               g.vp_diff_p2_minus_p1, g.git_sha,
               CASE WHEN d.player = g.winner THEN 1
                    WHEN g.winner = 0 THEN 0 ELSE -1 END AS decider_won
        FROM decisions d JOIN games g USING (game_id)
    """,
    # Per (game, player, round) VP deltas — the cheap intermediate signal that
    # makes per-round credit assignment possible without counterfactual replay.
    "round_vp": """
        SELECT game_id, player, round, SUM(points) AS points, COUNT(*) AS awards
        FROM vp_events GROUP BY game_id, player, round
    """,
    # Campaign-level rollup: one row per (fixture, arm) with the margin and its
    # spread. sd here is the raw per-game spread, NOT a paired standard error —
    # pairing lives in the A/B driver, not in the index.
    "arm_summary": """
        SELECT fixture, arm, git_sha, COUNT(*) AS games,
               SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed,
               SUM(CASE WHEN status <> 'completed' THEN 1 ELSE 0 END) AS stalled_or_error,
               ROUND(AVG(vp_diff_p2_minus_p1), 2) AS avg_margin_p2_minus_p1,
               ROUND(STDDEV_SAMP(vp_diff_p2_minus_p1), 2) AS sd_margin,
               ROUND(AVG(wall_seconds), 1) AS avg_wall_seconds
        FROM games GROUP BY fixture, arm, git_sha
    """,
    # Data-quality gate. Any nonzero dropped count means the ring buffer ate
    # decisions and that game's trace is biased toward its end.
    "data_quality": """
        SELECT game_id, fixture, arm, status, decision_batches_total,
               decision_batches_dropped, n_decisions, n_vp_events
        FROM games WHERE decision_batches_dropped > 0 OR n_decisions = 0
    """,
}


def write_tables(tables: dict[str, list[dict]], out_dir: str) -> dict:
    """Write Parquet via DuckDB when available, else CSV. Returns row counts."""
    os.makedirs(out_dir, exist_ok=True)
    counts = {name: len(rows) for name, rows in tables.items()}

    if duckdb is None:
        import csv
        for name, rows in tables.items():
            path = os.path.join(out_dir, name + ".csv")
            cols = sorted({k for r in rows for k in r}) or ["game_id"]
            with open(path, "w", newline="") as fh:
                w = csv.DictWriter(fh, fieldnames=cols)
                w.writeheader()
                w.writerows(rows)
        print("  duckdb not installed — wrote CSV instead of Parquet "
              "(pip install duckdb for the queryable season)")
        return counts

    db_path = os.path.join(out_dir, "season.duckdb")
    if os.path.exists(db_path):
        os.remove(db_path)
    con = duckdb.connect(db_path)
    try:
        for name, rows in tables.items():
            # Round-trip through JSON so DuckDB infers a schema even for the
            # empty case, and so heterogeneous/None fields do not break typing.
            tmp = os.path.join(out_dir, "_%s.jsonl" % name)
            with open(tmp, "w") as fh:
                for r in rows:
                    fh.write(json.dumps(r) + "\n")
            if rows:
                con.execute("CREATE TABLE %s AS SELECT * FROM read_json_auto(?)" % name, [tmp])
            else:
                con.execute("CREATE TABLE %s (game_id VARCHAR)" % name)
            con.execute("COPY %s TO '%s' (FORMAT PARQUET)"
                        % (name, os.path.join(out_dir, name + ".parquet")))
            os.remove(tmp)
        for name, sql in VIEWS.items():
            con.execute("CREATE VIEW %s AS %s" % (name, sql))
    finally:
        con.close()
    return counts


def build(season_dir: str, out_dir: str, quiet: bool = False) -> dict:
    paths = find_records(season_dir)
    tables = {"games": [], "decisions": [], "vp_events": []}
    skipped = []
    for p in paths:
        try:
            rec = load_record(p)
        except Exception as exc:  # noqa: BLE001
            skipped.append((p, "unreadable: %s" % exc))
            continue
        if rec.get("schema") != SCHEMA:
            skipped.append((p, "not a %s (schema=%r)" % (SCHEMA, rec.get("schema"))))
            continue
        tables["games"].append(game_row(rec, p))
        tables["decisions"].extend(decision_rows(rec))
        tables["vp_events"].extend(vp_rows(rec))

    counts = write_tables(tables, out_dir)
    result = {"season_dir": season_dir, "out_dir": out_dir,
              "records_found": len(paths), "skipped": skipped, "counts": counts}

    if not quiet:
        print("indexed %s -> %s" % (season_dir, out_dir))
        print("  records found: %d   skipped: %d" % (len(paths), len(skipped)))
        for name, n in counts.items():
            print("  %-10s %d rows" % (name, n))
        for p, why in skipped:
            print("  SKIP %s (%s)" % (os.path.basename(p), why))
        dropped = sum(1 for g in tables["games"] if g["decision_batches_dropped"] > 0)
        if dropped:
            print("  WARNING: %d game(s) dropped decision batches — see the "
                  "data_quality view" % dropped)
        if duckdb is not None:
            print("\n  query it:  duckdb %s" % os.path.join(out_dir, "season.duckdb"))
            print("             SELECT * FROM arm_summary;")
    return result


# ---------------------------------------------------------------------------
# selftest
# ---------------------------------------------------------------------------

SYNTHETIC = {
    "schema": SCHEMA,
    "schema_version": 1,
    "game_id": "selftest_game",
    "provenance": {
        "git_sha": "deadbee", "engine": "4.4.1.stable",
        "fixture": "mirror_orks_postdeploy", "fixture_sha256": "abc123",
        "p1_profile": {"path": "", "sha256": "", "inline": {}},
        "p2_profile": {"path": "p2.json", "sha256": "def456", "inline": {"parameters": {"X": 1}}},
        "difficulty": {"1": 2, "2": 2}, "seed": 4242, "time_scale": 6.0, "arm": "candidate",
    },
    "outcome": {
        "status": "completed", "note": "", "winner": 1, "vp_diff_p2_minus_p1": -7,
        "vp": {"player1": {"total": 66, "primary": 39, "secondary": 27},
               "player2": {"total": 59, "primary": 32, "secondary": 27}},
        "battle_round": 5, "actions_taken": 762, "wall_seconds": 414.8,
    },
    "vp_events": [
        {"round": 2, "phase": 9, "player": 1, "points": 5, "reason": "Primary: objectives"},
        {"round": 2, "phase": 9, "player": 2, "points": 3, "reason": "Secondary: Behind Enemy Lines"},
    ],
    "decisions": [{
        "round": 1, "phase_name": "movement", "player": 1,
        "records": [{
            "decision_type": "movement", "unit_id": "U_BOYZ_A", "unit_name": "Boyz",
            "candidates": [{"description": "advance to obj", "score": 12.5, "score_breakdown": {"obj": 10.0}},
                           {"description": "hold", "score": 9.0, "score_breakdown": {"obj": 9.0}}],
            "chosen_index": 1,  # deliberately NOT the best — exercises regret
            "parameters_used": {"MACRO_OBJECTIVE_WEIGHT": 1.5},
            "difficulty": "Hard", "context": {"phase": 2, "round": 1},
        }],
    }],
    "decision_batches_total": 1,
    "decision_batches_dropped": 0,
}


def selftest() -> int:
    tmp = tempfile.mkdtemp(prefix="ai_lab_selftest_")
    try:
        season = os.path.join(tmp, "season")
        os.makedirs(season)
        with open(os.path.join(season, "a.record.json"), "w") as fh:
            json.dump(SYNTHETIC, fh)
        # a second copy, gzipped, to prove both readers work
        with gzip.open(os.path.join(season, "b.record.json.gz"), "wt") as fh:
            rec = json.loads(json.dumps(SYNTHETIC))
            rec["game_id"] = "selftest_game_2"
            json.dump(rec, fh)
        # and a non-record file that must be skipped, not crash the run
        with open(os.path.join(season, "junk.record.json"), "w") as fh:
            json.dump({"schema": "something_else"}, fh)

        res = build(season, os.path.join(tmp, "idx"), quiet=True)
        fails = []

        def check(label, got, want):
            if got != want:
                fails.append("%s: got %r want %r" % (label, got, want))

        check("records_found", res["records_found"], 3)
        check("skipped", len(res["skipped"]), 1)
        check("games rows", res["counts"]["games"], 2)
        check("decision rows", res["counts"]["decisions"], 2)
        check("vp rows", res["counts"]["vp_events"], 4)

        rows = decision_rows(SYNTHETIC)
        check("chosen_score", rows[0]["chosen_score"], 9.0)
        check("best_score", rows[0]["best_score"], 12.5)
        check("regret", rows[0]["regret_vs_own_best"], 3.5)
        check("n_candidates", rows[0]["n_candidates"], 2)
        check("phase_name", rows[0]["phase_name"], "movement")

        g = game_row(SYNTHETIC, "x")
        check("vp_p1_total", g["vp_p1_total"], 66)
        check("margin", g["vp_diff_p2_minus_p1"], -7)
        check("fixture_sha256", g["fixture_sha256"], "abc123")
        check("n_decisions", g["n_decisions"], 1)

        # Regression: chosen_index 0 is the COMMON case (the AI took its
        # top-scoring candidate — 103 of 196 decisions in the first real game).
        # An `int(x or -1)` coercion mapped it to -1 because 0 is falsy, which
        # nulled chosen_score and regret for every one of them. The synthetic
        # case above deliberately picks index 1, so it could not catch this.
        top_pick = json.loads(json.dumps(SYNTHETIC))
        top_pick["decisions"][0]["records"][0]["chosen_index"] = 0
        tp = decision_rows(top_pick)[0]
        check("chosen_index 0 survives coercion", tp["chosen_index"], 0)
        check("chosen_score resolves at index 0", tp["chosen_score"], 12.5)
        check("regret is 0.0, not NULL, when the top candidate is taken",
              tp["regret_vs_own_best"], 0.0)

        # Same falsy-zero hazard on provenance ints: difficulty 0 is EASY and
        # seed 0 is a seed, so neither may be rewritten to the -1 sentinel.
        zeroes = json.loads(json.dumps(SYNTHETIC))
        zeroes["provenance"]["difficulty"] = {"1": 0, "2": 0}
        zeroes["provenance"]["seed"] = 0
        gz = game_row(zeroes, "x")
        check("difficulty 0 (EASY) is not rewritten to -1", gz["difficulty"], 0)
        check("seed 0 is not rewritten to -1", gz["seed"], 0)

        if duckdb is not None:
            con = duckdb.connect(os.path.join(tmp, "idx", "season.duckdb"))
            try:
                check("arm_summary games",
                      con.execute("SELECT games FROM arm_summary").fetchone()[0], 2)
                check("decision_outcomes rows",
                      con.execute("SELECT COUNT(*) FROM decision_outcomes").fetchone()[0], 2)
                check("round_vp rows",
                      con.execute("SELECT COUNT(*) FROM round_vp").fetchone()[0], 4)
                check("data_quality rows",
                      con.execute("SELECT COUNT(*) FROM data_quality").fetchone()[0], 0)
                # the join that is the point of the whole milestone
                check("joined margin",
                      con.execute("SELECT DISTINCT vp_diff_p2_minus_p1 FROM decision_outcomes")
                      .fetchone()[0], -7)
            finally:
                con.close()
        else:
            print("  (duckdb absent — view assertions skipped)")

        for f in fails:
            print("  FAIL %s" % f)
        print("selftest: %s (%d checks failed)" % ("PASS" if not fails else "FAIL", len(fails)))
        return 1 if fails else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("season_dir", nargs="?", help="directory of *.record.json[.gz]")
    ap.add_argument("--out", help="output dir (default: <season_dir>/_index)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()
    if not args.season_dir:
        ap.error("season_dir is required (or pass --selftest)")
    out = args.out or os.path.join(args.season_dir, "_index")
    build(args.season_dir, out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
