#!/bin/bash
# AI-vs-AI benchmark: play N full games headless and report win rate / VP
# differential. Use it to verify an AI change actually wins more games, or to
# compare parameter profiles (AIDecisionMaker load_player_profile format).
#
# Usage:
#   bash 40k/tests/run_ai_benchmark.sh [GAMES] [FIXTURE] [P1_PROFILE] [P2_PROFILE]
#
#   GAMES       number of games (default 3)
#   FIXTURE     save fixture to start from (default mirror_custodes_2000_postdeploy
#               — Lions of the Emperor on both sides, 2000 pts, round 1 Command,
#               post-deployment). Use mirror_custodes_2000_predeploy to start at
#               the DEPLOYMENT phase and have the AI place its own army.
#   P1_PROFILE / P2_PROFILE  optional parameter-override JSON paths
#
# Env overrides: BENCH_DIFFICULTY (default 1=Normal), BENCH_TIME_SCALE (3),
#   BENCH_MAX_SECONDS (600), BENCH_SEED_BASE (1000)
#
# M1 (AI learning loop) env overrides:
#   BENCH_DATA_DIR  if set, each game's `wh40k_ai_game_record` is gzipped and
#                   moved here, building a season directory that
#                   tools/ai_lab/build_index.py can turn into a queryable
#                   DuckDB. Unset = records stay in userdata.
#   BENCH_ARM       label recorded in every game record's provenance (e.g.
#                   "baseline" / "candidate"), so a season can be split by arm.
#   BENCH_KEEP_LOGS how many failed-game stdout logs to retain (default 50).
#                   Logs run 41-51 MB per game, so ~18 GB/day at 400 games —
#                   they are kept ONLY for stalled/errored games, gzipped.
#
# Output: per-game JSON under <godot-userdata>/test_results/bench/ + an
# aggregated bench_report.json/md, summary printed to stdout.

set -u

GAMES="${1:-3}"
FIXTURE="${2:-mirror_custodes_2000_postdeploy}"
P1_PROFILE="${3:-}"
P2_PROFILE="${4:-}"
DIFFICULTY="${BENCH_DIFFICULTY:-1}"
TIME_SCALE="${BENCH_TIME_SCALE:-3}"
MAX_SECONDS="${BENCH_MAX_SECONDS:-600}"
SEED_BASE="${BENCH_SEED_BASE:-1000}"
BENCH_DATA_DIR="${BENCH_DATA_DIR:-}"
BENCH_ARM="${BENCH_ARM:-}"
BENCH_KEEP_LOGS="${BENCH_KEEP_LOGS:-50}"

cd "$(dirname "$0")/.."
export PATH="$HOME/bin:$PATH"

# Provenance: which build actually played these games. Without it a season
# silently pools games from either side of a rules fix and the pooled effect
# is meaningless. build_index.py exposes git_sha so campaigns can pin it.
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    GIT_SHA="${GIT_SHA}-dirty"
fi

# Fixtures live in tests/saves but load from saves/
mkdir -p saves
cp -n tests/saves/*.w40ksave saves/ 2>/dev/null || true

# Resolve the userdata dir for this platform (where user:// lands)
USERDATA=$(godot --headless --path . --quit-after 1 2>/dev/null >/dev/null; echo "$HOME/.local/share/godot/app_userdata/40k")
if [ "$(uname)" = "Darwin" ]; then
    USERDATA="$HOME/Library/Application Support/Godot/app_userdata/40k"
fi
BENCH_DIR="$USERDATA/test_results/bench"
mkdir -p "$BENCH_DIR"

STAMP=$(date +%Y%m%d_%H%M%S)
echo "================================================================"
echo "AI benchmark: $GAMES game(s), fixture=$FIXTURE, difficulty=$DIFFICULTY"
echo "profiles: P1='${P1_PROFILE:-default}' P2='${P2_PROFILE:-default}'"
echo "git: $GIT_SHA  arm: '${BENCH_ARM:-none}'"
echo "================================================================"

# M0 gate: never learn on an unvalidated fixture. This is advisory here (the
# script is also used for one-off probes on scenario fixtures) but a campaign
# driver must treat a non-zero exit as fatal — a broken environment produces
# confident garbage, fast. See tools/ai_lab/fixture_check.py.
if ! python3 ../tools/ai_lab/fixture_check.py "$FIXTURE" >/tmp/fixture_check.$$ 2>&1; then
    echo "!!! FIXTURE CHECK FAILED for '$FIXTURE' — results are NOT safe to tune on:"
    sed 's/^/    /' /tmp/fixture_check.$$
    echo "!!! (mirrors are the campaign-eligible fixtures; see tools/ai_lab/fixture_check.py)"
fi
rm -f /tmp/fixture_check.$$

if [ -n "$BENCH_DATA_DIR" ]; then
    mkdir -p "$BENCH_DATA_DIR"
    echo "season records -> $BENCH_DATA_DIR"
fi
FAILED_LOG_DIR="$BENCH_DIR/failed_logs"

RESULTS=()
for i in $(seq 1 "$GAMES"); do
    SEED=$((SEED_BASE + i))
    OUT_REL="test_results/bench/${STAMP}_game_${i}.json"
    echo "--- game $i/$GAMES (seed $SEED) ---"
    ARGS=(--headless --path . -- --ai-benchmark
        "--bench-fixture=$FIXTURE" "--bench-seed=$SEED"
        "--bench-out=$OUT_REL" "--bench-difficulty=$DIFFICULTY"
        "--bench-time-scale=$TIME_SCALE" "--bench-max-seconds=$MAX_SECONDS"
        "--bench-git-sha=$GIT_SHA")
    [ -n "$P1_PROFILE" ] && ARGS+=("--bench-p1-profile=$P1_PROFILE")
    [ -n "$P2_PROFILE" ] && ARGS+=("--bench-p2-profile=$P2_PROFILE")
    [ -n "$BENCH_ARM" ] && ARGS+=("--bench-arm=$BENCH_ARM")

    # Capture the whole stdout rather than piping straight to grep: a stalled
    # game's log is the only artifact that explains WHY it stalled, and it is
    # gone once the process exits.
    GAME_LOG=$(mktemp "${TMPDIR:-/tmp}/aibench_${STAMP}_${i}_XXXXXX.log")
    timeout $((MAX_SECONDS + 120)) godot "${ARGS[@]}" > "$GAME_LOG" 2>&1
    grep -E "^\[AIBench\]" "$GAME_LOG" | tail -5

    RESULT_JSON="$BENCH_DIR/${STAMP}_game_${i}.json"
    RECORD_JSON="$BENCH_DIR/${STAMP}_game_${i}.record.json"
    RESULTS+=("$RESULT_JSON")

    STATUS=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status',''))" \
        "$RESULT_JSON" 2>/dev/null || echo "missing")

    # Keep the full log only when something went wrong — 41-51 MB/game means
    # "archive everything" is ~18 GB/day at 400 games/day.
    if [ "$STATUS" = "completed" ]; then
        rm -f "$GAME_LOG"
    else
        mkdir -p "$FAILED_LOG_DIR"
        gzip -c "$GAME_LOG" > "$FAILED_LOG_DIR/${STAMP}_game_${i}_${STATUS}.log.gz"
        rm -f "$GAME_LOG"
        echo "    kept failure log: $FAILED_LOG_DIR/${STAMP}_game_${i}_${STATUS}.log.gz"
        # prune to the newest BENCH_KEEP_LOGS
        ls -1t "$FAILED_LOG_DIR"/*.log.gz 2>/dev/null | tail -n +$((BENCH_KEEP_LOGS + 1)) \
            | while read -r old; do rm -f "$old"; done
    fi

    # Gzip the game record into the season directory.
    if [ -n "$BENCH_DATA_DIR" ] && [ -f "$RECORD_JSON" ]; then
        gzip -c "$RECORD_JSON" > "$BENCH_DATA_DIR/${STAMP}_game_${i}.record.json.gz"
        rm -f "$RECORD_JSON"
    fi
done

# Aggregate
python3 - "$BENCH_DIR/${STAMP}_report" "${RESULTS[@]}" <<'PYEOF'
import json, sys

report_base, paths = sys.argv[1], sys.argv[2:]
games = []
for p in paths:
    try:
        games.append(json.load(open(p)))
    except Exception as e:
        games.append({"status": "missing", "note": str(e), "path": p})

completed = [g for g in games if g.get("status") == "completed"]
stalled = [g for g in games if g.get("status") in ("stalled", "error", "missing")]
p1_wins = sum(1 for g in completed if g.get("winner") == 1)
p2_wins = sum(1 for g in completed if g.get("winner") == 2)
draws = sum(1 for g in completed if g.get("winner") == 0)
diffs = [g.get("vp_diff_p2_minus_p1", 0) for g in completed]
avg_diff = sum(diffs) / len(diffs) if diffs else 0.0

summary = {
    "games": len(games), "completed": len(completed), "stalled_or_error": len(stalled),
    "p1_wins": p1_wins, "p2_wins": p2_wins, "draws": draws,
    "avg_vp_diff_p2_minus_p1": round(avg_diff, 2),
    "per_game": [
        {"seed": g.get("seed"), "status": g.get("status"), "winner": g.get("winner"),
         "vp_p1": g.get("vp", {}).get("player1", {}).get("total"),
         "vp_p2": g.get("vp", {}).get("player2", {}).get("total"),
         "rounds": g.get("battle_round"), "actions": g.get("actions_taken"),
         "wall_seconds": round(g.get("wall_seconds", 0), 1), "note": g.get("note", "")}
        for g in games],
}
json.dump(summary, open(report_base + ".json", "w"), indent=2)

lines = ["# AI benchmark report", "",
         f"Games: {summary['games']} (completed {summary['completed']}, stalled/error {summary['stalled_or_error']})",
         f"P1 wins: {p1_wins}  P2 wins: {p2_wins}  Draws: {draws}",
         f"Avg VP diff (P2-P1): {summary['avg_vp_diff_p2_minus_p1']}", "",
         "| seed | status | winner | VP P1 | VP P2 | rounds | actions | wall s | note |",
         "|---|---|---|---|---|---|---|---|---|"]
for g in summary["per_game"]:
    lines.append("| {seed} | {status} | {winner} | {vp_p1} | {vp_p2} | {rounds} | {actions} | {wall_seconds} | {note} |".format(**g))
open(report_base + ".md", "w").write("\n".join(lines) + "\n")

print()
print("\n".join(lines))
print(f"\nreport: {report_base}.md")
PYEOF

echo "================================================================"
